#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest commit for Steel branch..."
LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/mattwparas/helix/branches/steel-event-system | jq -r ".commit.sha" | cut -c1-7)
echo "Obtained latest Steel version: $LATEST_TAG"


echo "Cloning Helix..."
git clone --branch steel-event-system https://github.com/mattwparas/helix.git src/helix
cd src/helix
echo "Updating git submodules for Steel..."
git submodule update --init --recursive


echo "Installing cargo-deb..."
cargo install cargo-deb --locked --version 3.4.0

# Set the runtime to standard location for packages as instructed internally by helix documentation
export HELIX_DEFAULT_RUNTIME=/usr/lib/helix/runtime

VERSION="${LATEST_TAG#v}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"

echo "Building Debian package with cargo-deb..."
export PATH="$HOME/.cargo/bin:$PATH"
echo "Compiling Helix-Steel with Cargo manually..."
cargo build --release --locked

cargo deb --no-build --deb-version "$VERSION" -- --locked

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
