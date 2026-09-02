#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Installing stable rustup toolchain to bypass system rustc restrictions..."
curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
export PATH="$HOME/.cargo/bin:$PATH"
rustup default stable

echo "Extracting Helix-Steel semantic version and Git hash..."
COMMIT_SHA=$(git ls-remote https://github.com/mattwparas/helix.git refs/heads/steel-event-system | cut -c1-7)
echo "SHA: $COMMIT_SHA"



echo "Cloning Helix..."
git clone --branch steel-event-system https://github.com/mattwparas/helix.git src/helix
cd src/helix
echo "Updating git submodules for Steel..."
git submodule update --init --recursive


echo "Installing cargo-deb..."
cargo install cargo-deb --locked --version 3.4.0
echo "Reading semantic version from Cargo.toml..."
SEM_VER=$(grep -m1 "^version = " Cargo.toml | cut -d """ -f 2)
echo "Obtained Semantic Version: $SEM_VER"
VERSION="${SEM_VER}+git${COMMIT_SHA}.${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"


# Set the runtime to standard location for packages as instructed internally by helix documentation
export HELIX_DEFAULT_RUNTIME=/usr/lib/helix/runtime

echo "VERSION=${VERSION}"

echo "Building Debian package with cargo-deb..."
export PATH="$HOME/.cargo/bin:$PATH"
echo "Compiling Helix-Steel with Cargo manually..."
cargo build --release --locked

export CARGO_NET_GIT_FETCH_WITH_CLI=true

cargo deb --no-build --deb-version "$VERSION" -- --locked
echo "Repackaging payload to rename package directly to hx..."
mkdir -p target/debian/repack
dpkg-deb -R target/debian/helix_*.deb target/debian/repack/
sed -i "s/^Package: helix$/Package: hx/" target/debian/repack/DEBIAN/control
rm target/debian/helix_*.deb
dpkg-deb -Zxz -b target/debian/repack/ "target/debian/hx_${VERSION}_amd64.deb"
rm -rf target/debian/repack/




echo "Moving .deb to workspace root..."
# Find the exact deb file in the debian targeted output
DEB_FILE=$(find target/debian -maxdepth 1 -name "helix_*.deb" | head -n 1)
if [ -n "$DEB_FILE" ]; then
  mv "$DEB_FILE" $GITHUB_WORKSPACE/
else
  echo "ERROR: .deb file not found in target/debian/"
  exit 1
fi

echo "Build finished successfully."
