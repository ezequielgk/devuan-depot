#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest Niri tag..."
LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/YaLTeR/niri/tags | jq -r '.[0].name')
echo "Obtained latest version: $LATEST_TAG"

echo "Cloning Niri..."
git clone --branch "$LATEST_TAG" --depth 1 https://github.com/YaLTeR/niri.git src
cd src

echo "Compiling Niri..."
cargo build --release

echo "Staging pkgroot..."
VERSION="${LATEST_TAG#v}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"

mkdir -p pkgroot/DEBIAN
mkdir -p pkgroot/usr/bin
mkdir -p pkgroot/usr/share/wayland-sessions

# Copy main binaries
cp target/release/niri pkgroot/usr/bin/
if [ -f target/release/niri-msg ]; then
  cp target/release/niri-msg pkgroot/usr/bin/
fi

# Copy the desktop file
if [ -f resources/niri.desktop ]; then
  cp resources/niri.desktop pkgroot/usr/share/wayland-sessions/
fi

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
Package: niri
Version: ${VERSION}
Section: x11
Priority: optional
Architecture: amd64
Depends: ${DEPS}
Recommends: xwayland-satellite
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: Niri - A scrollable-tiling Wayland compositor
 Niri is a scrollable-tiling Wayland compositor.
CTRL

cat > pkgroot/DEBIAN/postinst <<'EOF'
#!/bin/sh
set -e
if [ -x /usr/bin/update-desktop-database ]; then
  update-desktop-database -q /usr/share/applications || true
fi
exit 0
EOF

cat > pkgroot/DEBIAN/postrm <<'EOF'
#!/bin/sh
set -e
if [ -x /usr/bin/update-desktop-database ]; then
  update-desktop-database -q /usr/share/applications || true
fi
exit 0
EOF

chmod 755 pkgroot/DEBIAN/postinst pkgroot/DEBIAN/postrm

dpkg-deb --build --root-owner-group pkgroot "niri_${VERSION}_amd64.deb"
mv "niri_${VERSION}_amd64.deb" ..
echo "Build finished successfully."
