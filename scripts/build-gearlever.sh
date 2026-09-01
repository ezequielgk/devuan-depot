#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest GearLever tag..."
LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/mijorus/gearlever/releases/latest | jq -r '.tag_name')

if [ "$LATEST_TAG" = "null" ] || [ -z "$LATEST_TAG" ]; then
    echo "ERROR: Failed to fetch latest release tag"
    exit 1
fi
echo "Obtained latest version: $LATEST_TAG"

echo "Cloning GearLever..."
git clone --branch "$LATEST_TAG" --depth 1 https://github.com/mijorus/gearlever.git src/gearlever
cd src/gearlever

echo "Compiling GearLever with Meson..."
meson setup build --prefix=/usr
ninja -C build

echo "Staging pkgroot..."
mkdir -p ../../pkgroot/DEBIAN
DESTDIR=$PWD/../../pkgroot ninja -C build install
echo "Installing Python dependencies locally into the deb..."
apt-get install -y python3-pip
pip3 install desktop-entry-lib --target=$PWD/../../pkgroot/usr/lib/python3/dist-packages/ --no-user


cd ../..

echo "Writing control file and building .deb..."
VERSION="${LATEST_TAG#v}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"

# Manual dependencies since this is a Python app
DEPS="python3, python3-gi, gir1.2-gtk-4.0, gir1.2-adw-1, python3-requests, python3-xdg, squashfs-tools, dconf-gsettings-backend | gsettings-backend"

cat > pkgroot/DEBIAN/control <<CTRL
Package: gearlever
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: all
Depends: ${DEPS}
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: Manage AppImages with ease
 GearLever integrates AppImages into your app menu, handles updates
 and keeps them organized.
CTRL

cat > pkgroot/DEBIAN/postinst <<'POSTINST'
#!/bin/sh
set -e
if [ -x /usr/bin/glib-compile-schemas ]; then
  glib-compile-schemas /usr/share/glib-2.0/schemas || true
fi
if [ -x /usr/bin/update-desktop-database ]; then
  update-desktop-database -q /usr/share/applications || true
fi
if [ -x /usr/bin/gtk4-update-icon-cache ]; then
  gtk4-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
exit 0
POSTINST

cat > pkgroot/DEBIAN/postrm <<'POSTRM'
#!/bin/sh
set -e
if [ -x /usr/bin/glib-compile-schemas ]; then
  glib-compile-schemas /usr/share/glib-2.0/schemas || true
fi
if [ -x /usr/bin/update-desktop-database ]; then
  update-desktop-database -q /usr/share/applications || true
fi
if [ -x /usr/bin/gtk4-update-icon-cache ]; then
  gtk4-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
exit 0
POSTRM

chmod 755 pkgroot/DEBIAN/postinst pkgroot/DEBIAN/postrm

# Architecture is 'all' since it's Python
dpkg-deb --build --root-owner-group pkgroot "gearlever_${VERSION}_all.deb"
echo "Build finished successfully."
