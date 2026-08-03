#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest Gamescope tag..."
LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/ValveSoftware/gamescope/tags | jq -r '.[0].name')
echo "Obtained latest version: $LATEST_TAG"

echo "Cloning Gamescope..."
git clone --branch "$LATEST_TAG" --depth 1 --recursive https://github.com/ValveSoftware/gamescope.git src
cd src

echo "Configuring Gamescope..."
meson setup build/ --prefix=/usr --buildtype=release

echo "Compiling Gamescope..."
ninja -C build/

echo "Staging pkgroot..."
VERSION="${LATEST_TAG#v}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"

mkdir -p pkgroot/DEBIAN
DESTDIR=$PWD/pkgroot ninja -C build/ install

echo "Resolving shlib dependencies..."

mkdir -p debian
cat > debian/control <<CTRLSTUB
Source: gamescope
Section: x11
Priority: optional
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>

Package: gamescope
Architecture: amd64
Description: gamescope stub
CTRLSTUB

set -u
SO_TARGETS=$(find pkgroot/usr/bin pkgroot/usr/lib -type f \( -executable -o -name "*.so*" \) 2>/dev/null || true)
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
set +u

echo "Writing control file and building .deb..."
cat > pkgroot/DEBIAN/control <<CTRL
Package: gamescope
Version: ${VERSION}
Section: x11
Priority: optional
Architecture: amd64
Depends: ${DEPS}
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: Gamescope - SteamOS session compositing window manager
 Gamescope is the micro-compositor formerly known as steamcompmgr.
CTRL

dpkg-deb --build --root-owner-group pkgroot "gamescope_${VERSION}_amd64.deb"
mv "gamescope_${VERSION}_amd64.deb" ..
echo "Build finished successfully."
