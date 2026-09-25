#!/bin/sh
set -e
DWL_VERSION="v0.9"
WORKDIR="$(pwd)/src"
DWL_REPO="https://codeberg.org/dwl/dwl.git"
PATCHES_REPO="https://codeberg.org/dwl/dwl-patches.git"

PATCHES="ipc bar column btrtile centeredmaster vanitygaps pertag cfact attachbottom autostart swallow warpcursor hide_vacant_tags"

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"
git clone --branch "$DWL_VERSION" --depth 1 "$DWL_REPO" dwl
git clone --depth 1 "$PATCHES_REPO" dwl-patches

cd dwl
APPLIED=""

# Try to find the closest patch version dynamically
for name in $PATCHES; do
    pdir="../dwl-patches/patches/$name"
    if [ ! -d "$pdir" ]; then
        continue
    fi

    # Pick patch based on version if available, otherwise just use sort
    patch_file=$(ls "$pdir" | grep "v0.9\|0.9" | head -n 1)
    if [ -z "$patch_file" ]; then
        patch_file=$(ls "$pdir" | grep "v0.8\|0.8" | head -n 1)
    fi
    if [ -z "$patch_file" ]; then
        patch_file=$(find "$pdir" -maxdepth 1 -name '*.patch' -not -name '*-[0-9]*' | head -n1)
    fi
    if [ -z "$patch_file" ]; then
        patch_file=$(find "$pdir" -maxdepth 1 -name '*.patch' | sort | tail -n1)
    fi

    patch_path="$pdir/$patch_file"
    patch_path=$(basename "$patch_path")
    patch_path="$pdir/$patch_path"

    echo "==> Tratando de aplicar $name ($patch_path)..."
    if git apply --check "$patch_path" 2>/dev/null; then
        git apply "$patch_path"
        APPLIED="$APPLIED $name"
    else
        echo "--> Advertencia: El patch $name no aplica en $DWL_VERSION, se omitirá."
    fi
done

echo "==> Patches aplicados exitosamente: $APPLIED"

rm -rf .git ../dwl-patches
cd "$WORKDIR/.."
mkdir -p dwl-devuan-0.9
cp -r "$WORKDIR/dwl"/* dwl-devuan-0.9/
tar czf dwl-devuan_0.9.orig.tar.gz dwl-devuan-0.9
rm -rf dwl-devuan-0.9
