#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest SwayFX tag..."
LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/WillPower3309/swayfx/tags | jq -r '.[0].name')
echo "Obtained latest version: $LATEST_TAG"

echo "Cloning SwayFX..."
git clone --branch "$LATEST_TAG" --depth 1 https://github.com/WillPower3309/swayfx.git src
cd src

echo "Compiling SwayFX..."
meson setup build --buildtype=release --prefix=/usr
ninja -C build

echo "Staging pkgroot..."
# Remove 'v' from tag if present
VERSION="${LATEST_TAG#v}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"

mkdir -p pkgroot/DEBIAN
DESTDIR="$PWD/pkgroot" ninja -C build install

# Modify wayland-sessions desktop file
mv pkgroot/usr/share/wayland-sessions/sway.desktop pkgroot/usr/share/wayland-sessions/swayfx.desktop
cat > pkgroot/usr/share/wayland-sessions/swayfx.desktop <<'SESSION'
[Desktop Entry]
Name=SwayFX
Comment=An i3-compatible Wayland compositor with eye candy
Exec=dbus-run-session sway
Type=Application
SESSION

echo "Resolving shlib dependencies..."

mkdir -p debian
cat > debian/control <<CTRLSTUB
Source: swayfx
Section: x11
Priority: optional
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>

Package: swayfx
Architecture: amd64
Description: swayfx stub
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
Package: swayfx
Version: ${VERSION}
Section: x11
Priority: optional
Architecture: amd64
Depends: ${DEPS}
Recommends: seatd
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: SwayFX - Sway but with eye candy!
 Sway fork with blur, shadows and rounded corners.
 Based on Sway 1.12, wlroots 0.20.2 and scenefx 0.5.
 Built with Xwayland support enabled.
CTRL

cat > pkgroot/DEBIAN/postinst <<'EOF'
#!/bin/sh
set -e
ldconfig
if [ -x /usr/bin/update-desktop-database ]; then
  update-desktop-database -q /usr/share/applications || true
fi
exit 0
EOF

cat > pkgroot/DEBIAN/postrm <<'EOF'
#!/bin/sh
set -e
ldconfig
if [ -x /usr/bin/update-desktop-database ]; then
  update-desktop-database -q /usr/share/applications || true
fi
exit 0
EOF

chmod 755 pkgroot/DEBIAN/postinst pkgroot/DEBIAN/postrm

dpkg-deb --build --root-owner-group pkgroot "swayfx_${VERSION}_amd64.deb"
mv "swayfx_${VERSION}_amd64.deb" ..
echo "Build finished successfully."
