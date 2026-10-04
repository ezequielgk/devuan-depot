#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}
echo "Compiling wayland (amd64 + i386) for Steam..."

# We need source repos in apt
sed -i 's/^deb /deb-src /g' /etc/apt/sources.list.d/debian.sources || true
grep -q "^deb-src" /etc/apt/sources.list || echo "deb-src http://deb.debian.org/debian trixie main" >> /etc/apt/sources.list
dpkg --add-architecture i386
apt-get update

apt-get install -y dpkg-dev build-essential fakeroot devscripts
apt-get build-dep -y wayland
apt-get build-dep -y -a i386 wayland || true

mkdir -p src/wayland
cd src/wayland

# Pull debian sources
apt-get source wayland
cd wayland-*

# Build AMD64
dpkg-buildpackage -b -uc -us

# Build i386
dpkg-buildpackage -B -a i386 -uc -us

cd ..
mkdir -p ../../pkgroot
# Move only the specific libraries needed
cp libwayland-client0_*.deb ../../pkgroot/ || true
cp libwayland-server0_*.deb ../../pkgroot/ || true
cp libwayland-egl1_*.deb ../../pkgroot/ || true
cp libwayland-cursor0_*.deb ../../pkgroot/ || true

echo "Done building wayland libraries."
