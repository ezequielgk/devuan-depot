#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest scroll tag..."
LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/dawsers/scroll/releases | jq -r '.[].tag_name | select(contains("beta") | not)' | head -n 1)
if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" = "null" ]; then
  # Fallback to tags if no releases exist
  LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/dawsers/scroll/tags | jq -r '.[0].name')
fi

echo "Obtained latest version: $LATEST_TAG"

echo "Cloning scroll..."
git clone --branch "$LATEST_TAG" --depth 1 https://github.com/dawsers/scroll.git src/scroll
cd src/scroll

echo "Compiling scroll..."
# Devuan uses elogind instead of systemd, but we build on Debian CI so we link against libsystemd. Devuan's libsystemd0 package satisfies it natively via elogind.
meson setup build -Dprefix=/usr -Dsd-bus-provider=libsystemd -Dwerror=false -Db_ndebug=true
ninja -C build

echo "Staging pkgroot..."
COMMIT_HASH=$(git rev-parse --short HEAD)
echo "COMMIT_HASH=${COMMIT_HASH}"

mkdir -p pkgroot/DEBIAN
DESTDIR=$PWD/pkgroot ninja -C build install

echo "Resolving shlib dependencies..."

mkdir -p debian
cat > debian/control <<CTRLSTUB
Source: scroll
Section: x11
Priority: optional
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>

Package: scroll
Architecture: amd64
Description: scroll stub
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
Package: scroll
Version: ${VERSION}
Section: x11
Priority: optional
Architecture: amd64
Depends: ${DEPS:-libc6}
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: scroll - Wayland compositor forked from sway with scrolling layout
CTRL

dpkg-deb --build --root-owner-group pkgroot "scroll_${VERSION}_amd64.deb"
mv "scroll_${VERSION}_amd64.deb" ../..
echo "Build finished successfully."
