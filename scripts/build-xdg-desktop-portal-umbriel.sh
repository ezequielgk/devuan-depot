#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest commit for xdg-desktop-portal-umbriel..."
COMMITS_JSON=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/noctalia-dev/xdg-desktop-portal-umbriel/commits)

# Extract both full sha and a 7-char short sha
LATEST_SHA="$(echo "$COMMITS_JSON" | jq -r '.[0].sha')"
SHORT_SHA="${LATEST_SHA:0:7}"

if [ "$LATEST_SHA" = "null" ] || [ -z "$LATEST_SHA" ]; then
    echo "ERROR: Failed to fetch latest commit"
    exit 1
fi

echo "Obtained latest commit: $LATEST_SHA"

echo "Cloning xdg-desktop-portal-umbriel..."
git clone https://github.com/noctalia-dev/xdg-desktop-portal-umbriel.git src/xdp-umbriel
cd src/xdp-umbriel
git checkout $LATEST_SHA

# Fix for broken nlohmann-json vendoring missing detail headers
echo "Patching broken vendored json.hpp..."
curl -sL https://github.com/nlohmann/json/releases/download/v3.12.0/json.hpp -o src/vendor/json.hpp


echo "Patching broken vendored json.hpp..."
curl -sL https://github.com/nlohmann/json/releases/download/v3.12.0/json.hpp -o src/vendor/json.hpp


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
# Set formatting like 0.0.0+git20240401.abcdefg.1~devuandepot
DATE_STR=$(date -u +%Y%m%d)
VERSION="0.1.0+git${DATE_STR}.${RUN_NUMBER}.${SHORT_SHA}~devuandepot"
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

cat > pkgroot/DEBIAN/postinst <<'POSTINST_EOF'
#!/bin/sh
set -e
ldconfig
if [ -x /usr/bin/update-desktop-database ]; then
  update-desktop-database -q /usr/share/applications || true
fi
exit 0
POSTINST_EOF

cat > pkgroot/DEBIAN/postrm <<'POSTRM_EOF'
#!/bin/sh
set -e
ldconfig
if [ -x /usr/bin/update-desktop-database ]; then
  update-desktop-database -q /usr/share/applications || true
fi
exit 0
POSTRM_EOF

chmod 755 pkgroot/DEBIAN/postinst pkgroot/DEBIAN/postrm

dpkg-deb --build --root-owner-group pkgroot "xdg-desktop-portal-umbriel_${VERSION}_amd64.deb"
echo "Build finished successfully."
