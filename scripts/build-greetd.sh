#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest greetd tag..."
LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/kennylevinsen/greetd/tags | jq -r '.[0].name')
echo "Obtained latest version: $LATEST_TAG"

echo "Cloning greetd..."
git clone --branch "$LATEST_TAG" --depth 1 https://github.com/kennylevinsen/greetd.git src
cd src

echo "Compiling greetd..."
cargo build --release

echo "Staging pkgroot..."
VERSION="${LATEST_TAG#v}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"

mkdir -p pkgroot/DEBIAN
mkdir -p pkgroot/usr/bin
mkdir -p pkgroot/etc/greetd
mkdir -p pkgroot/etc/sv/greetd
mkdir -p pkgroot/etc/pam.d

cp target/release/greetd pkgroot/usr/bin/
cp target/release/agreety pkgroot/usr/bin/

if [ -f config.toml ]; then
  cp config.toml pkgroot/etc/greetd/config.toml
else
  cat << 'EOC' > pkgroot/etc/greetd/config.toml
[terminal]
vt = 1
[default_session]
command = "agreety --cmd /bin/sh"
user = "greeter"
EOC
fi

if [ -f greetd.pam ]; then
    cp greetd.pam pkgroot/etc/pam.d/greetd
else
cat << 'EOPAM' > pkgroot/etc/pam.d/greetd
#%PAM-1.0
auth      include   login
account   include   login
password  include   login
session   include   login
EOPAM
fi

cat << 'EORUN' > pkgroot/etc/sv/greetd/run
#!/bin/sh
[ ! -d /run/greetd ] && mkdir -p /run/greetd
exec greetd
EORUN
chmod +x pkgroot/etc/sv/greetd/run

echo "Resolving shlib dependencies..."

mkdir -p debian
cat > debian/control <<CTRLSTUB
Source: greetd
Section: x11
Priority: optional
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>

Package: greetd
Architecture: amd64
Description: greetd stub
CTRLSTUB

set -u
SO_TARGETS=$(find pkgroot/usr/bin -type f -executable -exec sh -c 'file "{}" | grep -q ELF' \; -print)
if [ -z "$SO_TARGETS" ]; then
  echo "ERROR: no executables found to scan"
  exit 1
fi
if ! RAW_DEPS=$(dpkg-shlibdeps -O $SO_TARGETS); then
  echo "ERROR: dpkg-shlibdeps failed"
  exit 1
fi
DEPS=$(printf '%s\n' "$RAW_DEPS" | sed 's/^shlibs:Depends=//')
echo "=== Resolved Depends: ${DEPS} ==="
if [ -z "$DEPS" ]; then
  echo "ERROR: dpkg-shlibdeps resolved an EMPTY Depends"
  exit 1
fi
# Adicionamos dependencias clave para login auth
DEPS="${DEPS}"
set +u

echo "Writing control file and building .deb..."
cat > pkgroot/DEBIAN/control <<CTRL
Package: greetd
Version: ${VERSION}
Section: admin
Priority: optional
Architecture: amd64
Depends: \${DEPS}, runit
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: greetd - minimal and flexible login manager daemon
 greetd is a minimal and flexible login manager daemon that makes no 
 assumptions about what you want to launch. Specially tailored for Runit.
CTRL

# Corregimos interpolación
sed -i "s/\${DEPS}/${DEPS}/g" pkgroot/DEBIAN/control

cat > pkgroot/DEBIAN/postinst <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
  # Create the greeter user if it doesn't exist
  if ! getent passwd greeter >/dev/null 2>&1; then
    useradd -M -G video -s /bin/false greeter || true
  fi
  chmod -R go+r /etc/greetd/
fi
exit 0
EOF

chmod 755 pkgroot/DEBIAN/postinst
chmod +x ../scripts/build-greetd.sh || true

dpkg-deb --build --root-owner-group pkgroot "greetd_${VERSION}_amd64.deb"
mv "greetd_${VERSION}_amd64.deb" ..
echo "Build finished successfully."
