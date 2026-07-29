#!/usr/bin/env bash
set -e

UPSTREAM_REPO="Castro-Fidel/PortProton_dpkg"
ASSET_NAME="portproton_amd64.deb"

echo "Downloading latest PortProton release..."
API_URL="https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest"
curl -sSL "$API_URL" -o release.json

DOWNLOAD_URL=$(jq -r --arg name "$ASSET_NAME" \
  '.assets[] | select(.name == $name) | .browser_download_url' release.json)

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
  echo "No se encontró el asset $ASSET_NAME en el último release." >&2
  exit 1
fi

echo "Downloading $DOWNLOAD_URL"
curl -sSL "$DOWNLOAD_URL" -o "$ASSET_NAME"

VERSION=$(dpkg-deb -f "$ASSET_NAME" Version)
echo "Detected version: $VERSION"

mv "$ASSET_NAME" "portproton_${VERSION}_amd64.deb"
echo "Build finished successfully."
