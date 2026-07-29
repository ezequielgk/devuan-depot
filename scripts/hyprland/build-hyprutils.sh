#!/usr/bin/env bash
set -e

export CC=clang-19
export CXX=clang++-19
export CFLAGS="-O3 -fPIC"
export CXXFLAGS="-O3 -fPIC"

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest hyprutils tag..."
LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/hyprwm/hyprutils/releases | jq -r '.[].tag_name | select(contains("beta") | not)' | head -n 1)
if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" = "null" ]; then
  # Fallback to tags if no releases exist
  LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/hyprwm/hyprutils/tags | jq -r '.[0].name')
fi

echo "Obtained latest version: $LATEST_TAG"

echo "Cloning hyprutils..."
git clone --branch "$LATEST_TAG" --depth 1 https://github.com/hyprwm/hyprutils.git src/hyprutils
cd src/hyprutils

echo "Compiling hyprutils..."
cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -B build
cmake --build build -j$(nproc)

echo "Staging pkgroot..."
COMMIT_HASH=$(git rev-parse --short HEAD)
echo "COMMIT_HASH=${COMMIT_HASH}"

mkdir -p pkgroot/DEBIAN
DESTDIR=$PWD/pkgroot cmake --install build

echo "Resolving shlib dependencies..."

mkdir -p debian
cat > debian/control <<CTRLSTUB
Source: hyprutils
Section: x11
Priority: optional
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>

Package: hyprutils
Architecture: amd64
Description: hyprutils stub
CTRLSTUB

set -u
SO_TARGETS=$(find pkgroot/usr/bin pkgroot/usr/lib -type f -name "*.so*" -o -executable 2>/dev/null || true)
if [ -n "$SO_TARGETS" ]; then
  if RAW_DEPS=$(dpkg-shlibdeps -O $SO_TARGETS 2>/dev/null); then
    DEPS=$(printf '%s\n' "$RAW_DEPS" | sed 's/^shlibs:Depends=//')
    echo "=== Resolved Depends: ${DEPS} ==="
  else
    echo "WARN: dpkg-shlibdeps failed, skipping auto deps"
  fi
fi
set +u

echo "Writing control file and building .deb..."
VERSION="${LATEST_TAG#v}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"

cat > pkgroot/DEBIAN/control <<CTRL
Package: hyprutils
Version: ${VERSION}
Section: x11
Priority: optional
Architecture: amd64
Depends: ${DEPS:-libc6}
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: hyprutils - Wayland compositor ecosystem
CTRL

dpkg-deb --build --root-owner-group pkgroot "hyprutils_${VERSION}_amd64.deb"
mv "hyprutils_${VERSION}_amd64.deb" ../..
echo "Build finished successfully."
