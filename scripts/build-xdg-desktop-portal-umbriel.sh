#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest release/tag for xdg-desktop-portal-umbriel..."
LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/noctalia-dev/xdg-desktop-portal-umbriel/releases | jq -r '.[0].tag_name')

if [ "$LATEST_TAG" = "null" ] || [ -z "$LATEST_TAG" ]; then
    LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/noctalia-dev/xdg-desktop-portal-umbriel/tags | jq -r '.[0].name')
fi

if [ "$LATEST_TAG" = "null" ] || [ -z "$LATEST_TAG" ]; then
    echo "ERROR: Failed to fetch latest tag"
    exit 1
fi

echo "Obtained latest version: $LATEST_TAG"

echo "Cloning xdg-desktop-portal-umbriel..."
git clone --branch "$LATEST_TAG" --depth 1 https://github.com/noctalia-dev/xdg-desktop-portal-umbriel.git src/xdp-umbriel
cd src/xdp-umbriel

echo "Compiling..."
meson setup build-release --buildtype=release --prefix=/usr --sysconfdir=/etc
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
Source: xdg-desktop-portal-umbriel
Section: x11
Priority: optional
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>

Package: xdg-desktop-portal-umbriel
Architecture: amd64
Description: xdg-desktop-portal-umbriel stub
CTRLSTUB

set -u
SO_TARGETS=$(find pkgroot/usr/libexec pkgroot/usr/bin -type f -executable 2>/dev/null || true)
if [ -z "$SO_TARGETS" ]; then
  echo "WARNING: no executables found to scan for shlibs (or maybe none exist in libexec/bin), looking broadly..."
  SO_TARGETS=$(find pkgroot/usr -type f -executable)
fi

if [ -n "$SO_TARGETS" ]; then
  if ! RAW_DEPS=$(dpkg-shlibdeps -O $SO_TARGETS); then
    echo "ERROR: dpkg-shlibdeps failed"
    exit 1
  fi
  DEPS=$(printf '%s\n' "$RAW_DEPS" | sed 's/^shlibs:Depends=//')
  echo "=== Resolved Depends: ${DEPS} ==="
else
  DEPS=""
  echo "=== No executables found, Depends will be empty ==="
fi
set +u

echo "Writing control file and building .deb..."
VERSION="${LATEST_TAG#v}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"

cat > pkgroot/DEBIAN/control <<CTRL
Package: xdg-desktop-portal-umbriel
Version: ${VERSION}
Section: x11
Priority: optional
Architecture: amd64
Depends: xdg-desktop-portal, ${DEPS}
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: xdg-desktop-portal backend for Umbriel
 An xdg-desktop-portal backend for the Umbriel compositor.
 Enables screen sharing, screenshots and more.
CTRL

cat > pkgroot/DEBIAN/postinst <<'EOF'
#!/bin/sh
set -e
ldconfig
if [ -x /usr/bin/update-desktop-database ]; then
  update-desktop-database -q /usr/share/applications || true
fi
# Re-trigger desktop portal reload in the user sessions potentially
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

dpkg-deb --build --root-owner-group pkgroot "xdg-desktop-portal-umbriel_${VERSION}_amd64.deb"
echo "Build finished successfully."
