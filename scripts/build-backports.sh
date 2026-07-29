#!/usr/bin/env bash
set -e

if [ -z "$DEBIAN_PKG" ]; then
  echo "ERROR: DEBIAN_PKG is not set."
  exit 1
fi

echo "Adding sid source repo..."
echo "deb-src http://deb.debian.org/debian sid main" > /etc/apt/sources.list.d/sid-src.list
apt-get update

mkdir build
cd build

echo "Installing build dependencies for $DEBIAN_PKG..."
apt-get build-dep -y "$DEBIAN_PKG/sid"

echo "Downloading and compiling $DEBIAN_PKG..."
apt-get source -b "$DEBIAN_PKG/sid"

echo "Moving generated debs..."
mv *.deb ..
cd ..

echo "Build finished successfully."
