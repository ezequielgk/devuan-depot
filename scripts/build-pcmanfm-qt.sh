#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

LATEST_TAG="2.1.0"
echo "Obtained latest version: $LATEST_TAG"

echo "Cloning PCManFM-Qt..."
git clone --branch "$LATEST_TAG" --depth 1 https://github.com/lxqt/pcmanfm-qt.git src
cd src

echo "Compiling PCManFM-Qt..."
mkdir build && cd build
cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)
cd ..

echo "Staging pkgroot..."
VERSION="${LATEST_TAG#v}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"

DESTDIR="$(pwd)/pkgroot"
(cd build && make install DESTDIR="$DESTDIR")
mkdir -p pkgroot/DEBIAN

echo "Resolving shlib dependencies..."

mkdir -p debian
cat > debian/control <<CTRLSTUB
Source: pcmanfm-qt
Section: x11
Priority: optional
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>

Package: pcmanfm-qt
Architecture: amd64
Description: pcmanfm-qt stub
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
Package: pcmanfm-qt
Version: ${VERSION}
Section: x11
Priority: optional
Architecture: amd64
Depends: ${DEPS}
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: PCManFM-Qt - extremely fast and lightweight file manager
 Extremely fast and lightweight file manager, part of LXQt.
CTRL

dpkg-deb --build --root-owner-group pkgroot "pcmanfm-qt_${VERSION}_amd64.deb"
mv "pcmanfm-qt_${VERSION}_amd64.deb" ..
echo "Build finished successfully."
