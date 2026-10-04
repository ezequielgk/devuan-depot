#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}
echo "Compiling libdrm (amd64 + i386) for Steam..."

# We need source repos in apt
sed -i 's/^deb /deb-src /g' /etc/apt/sources.list.d/debian.sources || true
grep -q "^deb-src" /etc/apt/sources.list || echo "deb-src http://deb.debian.org/debian trixie main" >> /etc/apt/sources.list
dpkg --add-architecture i386
apt-get update

apt-get install -y dpkg-dev build-essential fakeroot devscripts
apt-get build-dep -y libdrm
apt-get build-dep -y -a i386 libdrm || true

mkdir -p src/libdrm
cd src/libdrm

# Pull debian sources
apt-get source libdrm
cd libdrm-*

# Build AMD64
dpkg-buildpackage -b -uc -us

# Build i386
dpkg-buildpackage -B -a i386 -uc -us

cd ..
mkdir -p ../../pkgroot
# Move only the specific libraries needed
cp libdrm2_*.deb ../../pkgroot/ || true
cp libdrm-amdgpu1_*.deb ../../pkgroot/ || true
cp libdrm-intel1_*.deb ../../pkgroot/ || true
cp libdrm-radeon1_*.deb ../../pkgroot/ || true
cp libdrm-nouveau2_*.deb ../../pkgroot/ || true

echo "Done building libdrm libraries."
