#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}
echo "Compiling fuzzel..."

apt-get update
apt-get install -y git build-essential meson ninja-build pkg-config scdoc \
    libwayland-dev wayland-protocols \
    libpixman-1-dev libcairo2-dev libxkbcommon-dev libpng-dev librsvg2-dev \
    libfcft-dev

# Pull fuzzel
git clone https://codeberg.org/dnkl/fuzzel.git src/fuzzel
cd src/fuzzel
LATEST_TAG=$(git describe --tags --abbrev=0)
git checkout "$LATEST_TAG"

# Configure and build
mkdir -p build
meson setup build --buildtype=release \
    -Denable-cairo=enabled \
    -Dpng-backend=libpng \
    -Dsvg-backend=librsvg \
    --prefix=/usr
ninja -C build

echo "Staging pkgroot..."
mkdir -p ../../pkgroot/DEBIAN
DESTDIR=$PWD/../../pkgroot ninja -C build install

cd ../..

echo "Resolving shlib dependencies..."
SO_TARGETS=$(find pkgroot/usr/bin -type f -executable)
RAW_DEPS=$(dpkg-shlibdeps -O $SO_TARGETS)
DEPS=$(printf '%s\n' "$RAW_DEPS" | sed 's/^shlibs:Depends=//')

VERSION="${LATEST_TAG#v}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"

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
echo "Build finished successfully."
