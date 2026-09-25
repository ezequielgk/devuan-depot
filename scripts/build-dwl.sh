#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}
echo "Starting dwl-devuan build wrapping user specs..."

# 1. Bypass fetch-source.sh since we want the patched tree
cd dwl-devuan

# 2. Copy the patched tree and inject debian directory
mkdir -p build-env
cp -r ../dwl-patched build-env/dwl-devuan-0.9
cp -r debian build-env/dwl-devuan-0.9/

# 3. Modify version in changelog dynamically to reflect rolling CI count
cd build-env/dwl-devuan-0.9
CURRENT_DATE=$(date -u +%Y%m%d)
VERSION="0.9.${CURRENT_DATE}.${RUN_NUMBER}~devuandepot"

cat > debian/changelog <<CHANGELOG
dwl-devuan (${VERSION}) trixie; urgency=medium

  * Automated build with custom patches from dwl-patches.

 -- Ezequiel <ezequielgk@example.invalid>  $(date -R)
CHANGELOG

# Fix missing runit dependency inside control file as required by their debian config
sed -i 's/inotify-tools, build-essential,/inotify-tools, build-essential, runit,/g' debian/control

echo "Building package natively..."
dpkg-buildpackage -us -uc -b

echo "Moving generated package back..."
cd ../..
mv build-env/*.deb ../
echo "Build finished successfully."
