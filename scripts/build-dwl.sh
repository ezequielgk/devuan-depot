#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest dwl commit..."
LATEST_COMMIT=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/djpohly/dwl/commits/main | jq -r '.sha')
SHORT_HASH=${LATEST_COMMIT:0:7}
echo "Obtained latest version: $SHORT_HASH"

echo "Cloning dwl..."
git clone https://github.com/djpohly/dwl.git src/dwl
cd src/dwl

echo "Compiling dwl..."
make XWAYLAND="-DXWAYLAND" XLIBS="xcb xcb-icccm" PREFIX="/usr"

echo "Staging pkgroot..."
mkdir -p pkgroot/DEBIAN
make install DESTDIR="$PWD/pkgroot" PREFIX="/usr"

echo "Resolving shlib dependencies..."

cd ../..
mkdir -p debian
cat > debian/control <<CTRLSTUB
Source: dwl
Section: x11
Priority: optional
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>

Package: dwl
Architecture: amd64
Description: dwl stub
CTRLSTUB

set -u
SO_TARGETS=$(find src/dwl/pkgroot/usr/bin -type f -executable)
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
VERSION="main.${SHORT_HASH}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"

cat > src/dwl/pkgroot/DEBIAN/control <<CTRL
Package: dwl
Version: ${VERSION}
Section: x11
Priority: optional
Architecture: amd64
Depends: ${DEPS}
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: dwl - dwm for Wayland
 dwl is a compact, hackable compositor for Wayland based on wlroots.
 It is intended to fill the same space in the Wayland world that dwm
 does in X11, primarily in terms of functionality, and secondarily in
 terms of philosophy.
CTRL

cat > src/dwl/pkgroot/DEBIAN/postinst <<'EOF'
#!/bin/sh
set -e
ldconfig
if [ -x /usr/bin/update-desktop-database ]; then
  update-desktop-database -q /usr/share/applications || true
fi
exit 0
EOF

cat > src/dwl/pkgroot/DEBIAN/postrm <<'EOF'
#!/bin/sh
set -e
ldconfig
if [ -x /usr/bin/update-desktop-database ]; then
  update-desktop-database -q /usr/share/applications || true
fi
exit 0
EOF

chmod 755 src/dwl/pkgroot/DEBIAN/postinst src/dwl/pkgroot/DEBIAN/postrm

dpkg-deb --build --root-owner-group src/dwl/pkgroot "dwl_${VERSION}_amd64.deb"
echo "Build finished successfully."
