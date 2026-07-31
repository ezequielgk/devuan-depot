#!/usr/bin/env bash
set -e

# Default values if not set in environment
KERNEL_SOURCE_VERSION=${KERNEL_SOURCE_VERSION:-}
LOCALVERSION=${LOCALVERSION:--crystal}

echo "Enabling deb-src to download kernel source..."
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
  sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources
else
  echo "deb-src http://deb.debian.org/debian trixie main" >> /etc/apt/sources.list
fi
apt-get update

# Save the repo root
REPO_ROOT=$(pwd)

echo "Downloading linux source package..."
mkdir -p /build && cd /build
if [ -n "$KERNEL_SOURCE_VERSION" ]; then
  apt-get source linux=$KERNEL_SOURCE_VERSION
else
  apt-get source linux
fi

# Find the extracted source directory
ls -d linux-*/ | head -1 > /build/srcdir.txt
SRCDIR=$(cat /build/srcdir.txt)
echo "Source directory: $SRCDIR"

# We must be in the repository root when running this script
if [ ! -f "$REPO_ROOT/kernel-config/.config" ]; then
  echo "Error: kernel-config/.config is missing in the repo."
  echo "Generate it on your machine with localmodconfig + menuconfig and commit it."
  exit 1
fi

echo "Copying committed .config..."
cp "$REPO_ROOT/kernel-config/.config" "/build/${SRCDIR}.config"

echo "Adapting config to this exact source version..."
cd "/build/${SRCDIR}"
make olddefconfig

echo "Compiling (.deb with intact Debian/Devuan hooks)..."
export PATH="/usr/lib/ccache:$PATH"
make -j$(nproc) bindeb-pkg LOCALVERSION="$LOCALVERSION"

echo "Gathering generated .deb files..."
cd /build
mkdir -p dist
mv /build/linux-image-*.deb dist/ 2>/dev/null || true
mv /build/linux-headers-*.deb dist/ 2>/dev/null || true
mv /build/linux-libc-dev*.deb dist/ 2>/dev/null || true
ls -lh dist/

echo "Generating checksums..."
cd dist
sha256sum *.deb > SHA256SUMS.txt

# Move dist to the repo workspace so the workflow can upload it
mv /build/dist "$REPO_ROOT/"
