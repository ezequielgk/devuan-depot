#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}
echo "Compiling wayland (amd64)..."

# We need source repos in apt
sed -i 's/^deb /deb-src /g' /etc/apt/sources.list.d/debian.sources || true
grep -q "^deb-src" /etc/apt/sources.list || echo "deb-src http://deb.debian.org/debian trixie main" >> /etc/apt/sources.list
apt-get update

apt-get install -y dpkg-dev build-essential fakeroot devscripts cmake pkg-config
apt-get build-dep -y wayland

mkdir -p src/wayland
cd src/wayland

# Pull debian sources
apt-get source wayland
cd wayland-*

# Build AMD64
dpkg-buildpackage -b -uc -us

cd ..
# Move only the specific libraries needed to the root
cp libwayland-client0_*.deb ../../ || true
cp libwayland-server0_*.deb ../../ || true
cp libwayland-egl1_*.deb ../../ || true
cp libwayland-cursor0_*.deb ../../ || true

echo "Done building wayland libraries."
