#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest Helix tag..."
LATEST_TAG=$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/helix-editor/helix/releases/latest | jq -r '.tag_name')

if [ "$LATEST_TAG" = "null" ] || [ -z "$LATEST_TAG" ]; then
    echo "ERROR: Failed to fetch latest release tag"
    exit 1
fi
echo "Obtained latest version: $LATEST_TAG"

echo "Cloning Helix..."
git clone --branch "$LATEST_TAG" --depth 1 https://github.com/helix-editor/helix.git src/helix
cd src/helix

echo "Installing cargo-deb..."
cargo install cargo-deb

# Set the runtime to standard location for packages as instructed internally by helix documentation
export HELIX_DEFAULT_RUNTIME=/usr/lib/helix/runtime

VERSION="${LATEST_TAG#v}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "VERSION=${VERSION}"

echo "Building Debian package with cargo-deb..."
export PATH="$HOME/.cargo/bin:$PATH"
cargo deb --deb-version "$VERSION" -- --locked

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
