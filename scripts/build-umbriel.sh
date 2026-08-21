#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest Umbriel release/tag..."
LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/noctalia-dev/umbriel/releases | jq -r '.[0].tag_name')

if [ "$LATEST_TAG" = "null" ] || [ -z "$LATEST_TAG" ]; then
    # Fallback to tags if no releases are found (since it's young)
    LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/noctalia-dev/umbriel/tags | jq -r '.[0].name')
fi

if [ "$LATEST_TAG" = "null" ] || [ -z "$LATEST_TAG" ]; then
    echo "ERROR: Failed to fetch latest tag"
    exit 1
fi

echo "Obtained latest version: $LATEST_TAG"

echo "Cloning umbriel..."
git clone --branch "$LATEST_TAG" --depth 1 https://github.com/noctalia-dev/umbriel.git src/umbriel
cd src/umbriel

echo "Fetching scenefx submodule..."
git submodule update --init

echo "Compiling umbriel..."
# Configure with meson directly to set prefix and options
meson setup build-release --buildtype=release --prefix=/usr -Djemalloc=enabled
ninja -C build-release

echo "Staging pkgroot..."
COMMIT_HASH=$(git rev-parse --short HEAD)
echo "COMMIT_HASH=${COMMIT_HASH}"

mkdir -p ../../pkgroot/DEBIAN
DESTDIR=$PWD/../../pkgroot ninja -C build-release install

cd ../..

echo "Resolving shlib dependencies..."
mkdir -p debian
cat > debian/control <<CTRLSTUB
Source: umbriel
Section: x11
Priority: optional
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>

Package: umbriel
Architecture: amd64
Description: umbriel stub
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
Package: umbriel
Version: ${VERSION}
Section: x11
Priority: optional
Architecture: amd64
Depends: ${DEPS}
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: Umbriel - A Wayland compositor designed for daily use
 Umbriel is a Wayland compositor designed for daily use, with scrolling and dwindle layouts, 
 per-output workspaces, window rules, blur, shadows, and fluid animations.
 It runs independently and can be paired with Noctalia.
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

dpkg-deb --build --root-owner-group pkgroot "umbriel_${VERSION}_amd64.deb"
echo "Build finished successfully."
