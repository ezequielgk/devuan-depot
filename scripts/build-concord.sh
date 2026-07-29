#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Installing latest Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
export PATH="$HOME/.cargo/bin:$PATH"

echo "Getting latest Concord tag..."
LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/chojs23/concord/tags | jq -r '.[0].name')
echo "Obtained latest version: $LATEST_TAG"

echo "Cloning Concord..."
git clone --branch "$LATEST_TAG" --depth 1 https://github.com/chojs23/concord.git src
cd src

echo "Compiling Concord..."
cargo build --release

echo "Staging pkgroot..."
VERSION="${LATEST_TAG#v}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"

mkdir -p pkgroot/DEBIAN pkgroot/usr/bin
cp target/release/concord pkgroot/usr/bin/

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
Package: concord
Version: ${VERSION}
Section: x11
Priority: optional
Architecture: amd64
Depends: ${DEPS}
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: Concord - A Discord terminal client
 Concord is a fast and simple terminal Discord client written in Rust.
CTRL

dpkg-deb --build --root-owner-group pkgroot "concord_${VERSION}_amd64.deb"
mv "concord_${VERSION}_amd64.deb" ..
echo "Build finished successfully."
