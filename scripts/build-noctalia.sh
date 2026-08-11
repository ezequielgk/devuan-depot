#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest Noctalia release..."
RELEASE_JSON=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/noctalia-dev/noctalia/releases/latest)
LATEST_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name')

if [ "$LATEST_TAG" = "null" ] || [ -z "$LATEST_TAG" ]; then
    echo "ERROR: Failed to fetch latest release tag"
    exit 1
fi

echo "Obtained latest version: $LATEST_TAG"

echo "Cloning noctalia..."
git clone --branch "$LATEST_TAG" --depth 1 https://github.com/noctalia-dev/noctalia.git src/noctalia
cd src/noctalia

echo "Compiling noctalia..."
# Configure with meson directly to disable tests, set prefix, and enable extreme optimizations
meson setup build-release --buildtype=release --prefix=/usr -Dtests=disabled -Db_lto=true -Djemalloc=enabled
ninja -C build-release

echo "Staging pkgroot..."
COMMIT_HASH=$(git rev-parse --short HEAD)
echo "COMMIT_HASH=${COMMIT_HASH}"

mkdir -p ../../pkgroot/DEBIAN
# Install to pkgroot
DESTDIR=$PWD/../../pkgroot ninja -C build-release install

cd ../..

echo "Resolving shlib dependencies..."
mkdir -p debian
cat > debian/control <<CTRLSTUB
Source: noctalia
Section: x11
Priority: optional
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>

Package: noctalia
Architecture: amd64
Description: noctalia stub
CTRLSTUB

set -u
SO_TARGETS=$(find pkgroot/usr/bin -type f -executable)
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
# Add optional runtime dependencies requested by user
DEPS="${DEPS}, ddcutil, usbutils"
set +u

echo "Writing control file and building .deb..."
VERSION="${LATEST_TAG#v}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"

cat > pkgroot/DEBIAN/control <<CTRL
Package: noctalia
Version: ${VERSION}
Section: x11
Priority: optional
Architecture: amd64
Depends: ${DEPS}
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: Noctalia - A native Wayland desktop shell
 Noctalia is a native Wayland desktop shell for people who want a polished, 
 configurable Linux desktop without stitching together a separate bar, 
 launcher, notification daemon, lock screen, wallpaper tool, and settings UI.
CTRL

cat > pkgroot/DEBIAN/postinst <<'EOF'
#!/bin/sh
set -e
ldconfig
if [ -x /usr/bin/update-desktop-database ]; then
  update-desktop-database -q /usr/share/applications || true
fi
exit 0
EOF

cat > pkgroot/DEBIAN/postrm <<'EOF'
#!/bin/sh
set -e
ldconfig
if [ -x /usr/bin/update-desktop-database ]; then
  update-desktop-database -q /usr/share/applications || true
fi
exit 0
EOF

chmod 755 pkgroot/DEBIAN/postinst pkgroot/DEBIAN/postrm
chmod +x scripts/build-noctalia.sh || true

dpkg-deb --build --root-owner-group pkgroot "noctalia_${VERSION}_amd64.deb"
echo "Build finished successfully."
