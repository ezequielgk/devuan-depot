#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest mangowm tag..."
LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/mangowm/mango/tags | jq -r '.[0].name')
echo "Obtained latest version: $LATEST_TAG"

echo "Cloning mangowm..."
git clone --branch "$LATEST_TAG" --depth 1 https://github.com/mangowm/mango.git src/mango
cd src/mango

echo "Compiling mango..."
meson setup build --buildtype=release --prefix=/usr --wrap-mode=default -Dwerror=false
ninja -C build

echo "Staging pkgroot..."
COMMIT_HASH=$(git rev-parse --short HEAD)
echo "COMMIT_HASH=${COMMIT_HASH}"

mkdir -p pkgroot/DEBIAN
DESTDIR=$PWD/pkgroot ninja -C build install

echo "Resolving shlib dependencies..."

mkdir -p debian
cat > debian/control <<CTRLSTUB
Source: mangowc
Section: x11
Priority: optional
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>

Package: mangowc
Architecture: amd64
Description: mangowc stub
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
VERSION="${LATEST_TAG#v}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"

cat > pkgroot/DEBIAN/control <<CTRL
Package: mangowc
Version: ${VERSION}
Section: x11
Priority: optional
Architecture: amd64
Depends: ${DEPS}
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: mangowc - Practical and Powerful wayland compositor (dwm but wayland)
 Practical and Powerful wayland compositor (dwm but wayland).
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

dpkg-deb --build --root-owner-group pkgroot "mangowc_${VERSION}_amd64.deb"
mv "mangowc_${VERSION}_amd64.deb" ../..
echo "Build finished successfully."
