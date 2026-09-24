#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest Noctalia Greeter release..."
LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/noctalia-dev/noctalia-greeter/tags | jq -r '.[0].name')

if [ "$LATEST_TAG" = "null" ] || [ -z "$LATEST_TAG" ]; then
    echo "ERROR: Failed to fetch latest release tag"
    exit 1
fi

echo "Obtained latest version: $LATEST_TAG"

echo "Cloning noctalia-greeter..."
git clone --branch "$LATEST_TAG" --depth 1 https://github.com/noctalia-dev/noctalia-greeter.git src/noctalia-greeter
cd src/noctalia-greeter

echo "Compiling noctalia-greeter..."
meson setup build-release --buildtype=plain --prefix=/usr --sysconfdir=/etc --strip
ninja -C build-release

echo "Staging pkgroot..."
COMMIT_HASH=$(git rev-parse --short HEAD)
echo "COMMIT_HASH=${COMMIT_HASH}"

mkdir -p ../../pkgroot/DEBIAN
DESTDIR=$PWD/../../pkgroot ninja -C build-release install

cd ../..

echo "Resolving shlib dependencies..."
mkdir -p debian
cat > debian/control <<CTRLSTUB
Source: noctalia-greeter
Section: x11
Priority: optional
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>

Package: noctalia-greeter
Architecture: amd64
Description: noctalia-greeter stub
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
# Add required runtime dependencies
DEPS="${DEPS}, greetd"
set +u

echo "Writing control file and building .deb..."
VERSION="${LATEST_TAG#v}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"

cat > pkgroot/DEBIAN/control <<CTRL
Package: noctalia-greeter
Version: ${VERSION}
Section: x11
Priority: optional
Architecture: amd64
Depends: ${DEPS}
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: A minimal login greeter for greetd that matches Noctalia Shell
 A minimal login greeter for greetd that matches the look and feel of Noctalia Shell.
CTRL

cat > pkgroot/DEBIAN/postinst <<'INNER_EOF'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
  if [ -x /usr/share/noctalia-greeter/setup_greeter_system.sh ]; then
    /usr/share/noctalia-greeter/setup_greeter_system.sh || true
  fi
fi
exit 0
INNER_EOF

cat > pkgroot/DEBIAN/postrm <<'INNER_EOF'
#!/bin/sh
set -e
if [ "$1" = "purge" ] || [ "$1" = "remove" ]; then
  rm -rf /var/lib/noctalia-greeter 2>/dev/null || true
fi
exit 0
INNER_EOF

chmod 755 pkgroot/DEBIAN/postinst pkgroot/DEBIAN/postrm
chmod +x scripts/build-noctalia-greeter.sh || true

dpkg-deb --build --root-owner-group pkgroot "noctalia-greeter_${VERSION}_amd64.deb"
echo "Build finished successfully."
