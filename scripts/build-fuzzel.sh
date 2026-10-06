#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest fuzzel tag..."
LATEST_TAG=$(git ls-remote --tags --sort=v:refname https://codeberg.org/dnkl/fuzzel.git | grep -v "\^{}" | tail -n 1 | awk -F/ '{print $3}')
echo "Obtained latest version: $LATEST_TAG"

rm -rf src
echo "Cloning fuzzel..."
git clone --branch "$LATEST_TAG" --depth 1 https://codeberg.org/dnkl/fuzzel.git src
cd src

echo "Compiling fuzzel..."
meson setup build --buildtype=release \
    --prefix=/usr \
    --sysconfdir=/etc \
    --strip \
    -Db_lto=true \
    -Db_ndebug=true \
    -Db_pie=true \
    -Denable-cairo=enabled \
    -Dpng-backend=libpng \
    -Dsvg-backend=librsvg
ninja -C build

echo "Staging pkgroot..."
VERSION="${LATEST_TAG#v}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"

DESTDIR="$(pwd)/pkgroot"
DESTDIR="$DESTDIR" ninja -C build install
mkdir -p pkgroot/DEBIAN

echo "Resolving shlib dependencies..."
mkdir -p debian
cat > debian/control <<CTRLSTUB
Source: fuzzel
Section: x11
Priority: optional
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>

Package: fuzzel
Architecture: amd64
Description: fuzzel stub
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
set +u

echo "Writing control file and building .deb..."
cat > pkgroot/DEBIAN/control <<CTRL
Package: fuzzel
Version: ${VERSION}
Section: x11
Priority: optional
Architecture: amd64
Depends: ${DEPS}
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: Wayland-native application launcher and fuzzy finder
 Fuzzel is a Wayland-native application launcher and fuzzy finder,
 inspired by rofi and dmenu.
CTRL

dpkg-deb --build --root-owner-group pkgroot "fuzzel_${VERSION}_amd64.deb"
mv "fuzzel_${VERSION}_amd64.deb" ..
echo "Build finished successfully."
