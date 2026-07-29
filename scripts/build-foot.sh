#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest Foot tag..."
LATEST_TAG=$(git ls-remote --tags --sort=v:refname https://codeberg.org/dnkl/foot.git | grep -v "\^{}" | tail -n 1 | awk -F/ '{print $3}')
echo "Obtained latest version: $LATEST_TAG"

echo "Cloning Foot..."
git clone --branch "$LATEST_TAG" --depth 1 https://codeberg.org/dnkl/foot.git src
cd src

echo "Compiling Foot..."
export CFLAGS="$CFLAGS -O3"
meson setup build --buildtype=release --prefix=/usr -Db_lto=true -Dterminfo=disabled
ninja -C build

echo "Staging pkgroot..."
VERSION="${LATEST_TAG#v}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"
DESTDIR="$(pwd)/pkgroot"
DESTDIR="$DESTDIR" ninja -C build install
mkdir -p pkgroot/DEBIAN

echo "Resolving shlib dependencies..."
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
Package: foot
Version: ${VERSION}
Section: x11
Priority: optional
Architecture: amd64
Depends: ${DEPS}
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: Foot - A fast, lightweight and minimalistic Wayland terminal emulator
 A fast, lightweight and minimalistic Wayland terminal emulator.
CTRL

dpkg-deb --build --root-owner-group pkgroot "foot_${VERSION}_amd64.deb"
mv "foot_${VERSION}_amd64.deb" ..
echo "Build finished successfully."
