#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest Umbriel release..."
RELEASE_JSON=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/noctalia-dev/umbriel/releases/latest)
LATEST_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name')

# Si la api da nulo (por ejemplo si umbriel no usa releases si no solo tags)
if [ "$LATEST_TAG" = "null" ] || [ -z "$LATEST_TAG" ]; then
    echo "Falling back to tags API..."
    LATEST_TAG=$(git ls-remote --tags https://github.com/noctalia-dev/umbriel.git | grep -v "\^{}" | awk -F/ '{print $3}' | sort -V | tail -n1)
fi

echo "Obtained latest version: $LATEST_TAG"
echo "Cloning umbriel..."
if [ -n "$LATEST_TAG" ]; then
  git clone --branch "$LATEST_TAG" --depth 1 https://github.com/noctalia-dev/umbriel.git src/umbriel

echo "Applying C++23 strict constness fix for libinput 1.26..."
sed -i "s/configuredProfile->points.data()/const_cast<double*>(configuredProfile->points.data())/g" src/umbriel/src/server/server_events.cpp
else
  echo "No tag found. Cloning main branch..."
  git clone --depth 1 https://github.com/noctalia-dev/umbriel.git src/umbriel

echo "Applying C++23 strict constness fix for libinput 1.26..."
sed -i "s/configuredProfile->points.data()/const_cast<double*>(configuredProfile->points.data())/g" src/umbriel/src/server/server_events.cpp
  MESON_VER=$(curl -sL https://raw.githubusercontent.com/noctalia-dev/umbriel/main/meson.build | grep -oP "(?<=version: ')[^']+")
  LATEST_TAG="${MESON_VER}+git$(date -u +%Y%m%d).$(git ls-remote https://github.com/noctalia-dev/umbriel.git HEAD | cut -c1-7)"
fi
# dummy comment to fix syntax https://github.com/noctalia-dev/umbriel.git src/umbriel
cd src/umbriel

echo "Compiling umbriel..."
meson setup build-release --buildtype=release --prefix=/usr -Dtests=disabled
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
if ! RAW_DEPS=$(dpkg-shlibdeps -O $SO_TARGETS); then
  echo "ERROR: dpkg-shlibdeps failed"
  exit 1
fi
DEPS=$(printf '%s\n' "$RAW_DEPS" | sed 's/^shlibs:Depends=//')
echo "=== Resolved Depends: ${DEPS} ==="
# Adding recommended deps
DEPS="${DEPS}, xwayland-satellite"
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
Description: A Wayland compositor built on wlroots.
 Umbriel is a Wayland compositor built on wlroots.
 Developed by the Noctalia project.
CTRL

chmod +x scripts/build-umbriel.sh || true
dpkg-deb --build --root-owner-group pkgroot "umbriel_${VERSION}_amd64.deb"
echo "Build finished successfully."
