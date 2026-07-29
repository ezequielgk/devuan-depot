#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Cloning xwayland-satellite..."
git clone --branch v0.8.1 --depth 1 https://github.com/Supreeeme/xwayland-satellite.git src
cd src

echo "Compiling..."
cargo build --release --locked

echo "Staging pkgroot..."
VERSION="0.8.1.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"

mkdir -p pkgroot/DEBIAN pkgroot/usr/bin
cp target/release/xwayland-satellite pkgroot/usr/bin/

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
FINAL_DEPS="${DEPS}, xwayland"
echo "=== Final Depends: ${FINAL_DEPS} ==="

cat > pkgroot/DEBIAN/control <<CTRL
Package: xwayland-satellite
Version: ${VERSION}
Section: x11
Priority: optional
Architecture: amd64
Depends: ${FINAL_DEPS}
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: xwayland-satellite - Xwayland rootless para niri
 Provee integracion Xwayland sin systemd para compositores
 Wayland que no la implementan de forma nativa (ej. niri).
CTRL

dpkg-deb --build --root-owner-group pkgroot "xwayland-satellite_${VERSION}_amd64.deb"
mv "xwayland-satellite_${VERSION}_amd64.deb" ..
echo "Build finished successfully."
