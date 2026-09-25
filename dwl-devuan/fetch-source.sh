#!/bin/sh
set -e

DWL_VERSION="v0.9"
WORKDIR="$(pwd)/src"
DWL_REPO="https://codeberg.org/dwl/dwl.git"
PATCHES_REPO="https://codeberg.org/dwl/dwl-patches.git"
MANIFEST="PATCHES-APPLIED.txt"

# Mandatory patches (will abort if they fail)
BLOCKING_PATCHES="bar foreign-toplevel-management column"

# QoL patches (can be skipped with a warning)
QOL_PATCHES="ipc btrtile centeredmaster vanitygaps pertag cfact attachbottom autostart swallow warpcursor hide_vacant_tags"

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"
echo "==> Clonando dwl ($DWL_VERSION)..."
git clone --branch "$DWL_VERSION" --depth 1 "$DWL_REPO" dwl
echo "==> Clonando dwl-patches..."
git clone --depth 1 "$PATCHES_REPO" dwl-patches

cd dwl
APPLIED=""
echo -e "PATCH\tSTATUS\tREASON" > "../$MANIFEST"

apply_patch_logic() {
    local name="$1"
    local is_blocking="$2"
    local pdir="../dwl-patches/patches/$name"
    
    if [ ! -d "$pdir" ]; then
        echo -e "$name\tSKIPPED\tDirectory not found in dwl-patches" >> "../$MANIFEST"
        if [ "$is_blocking" = "1" ]; then
            echo "ERROR BLOQUEANTE: No se encontró el patch '$name'." >&2
            exit 1
        fi
        return
    fi
    
    # Try to pick the correct patch file natively (prioritize v0.9 > v0.8 > main *.patch)
    local patch_file
    patch_file=$(ls "$pdir" | grep "v0.9\|0.9" | head -n 1)
    if [ -z "$patch_file" ]; then
        patch_file=$(ls "$pdir" | grep "v0.8\|0.8" | head -n 1)
    fi
    if [ -z "$patch_file" ]; then
        patch_file=$(find "$pdir" -maxdepth 1 -name '*.patch' -not -name '*-[0-9]*' | head -n1 | xargs -r basename)
    fi
    if [ -z "$patch_file" ]; then
        patch_file=$(find "$pdir" -maxdepth 1 -name '*.patch' | sort | tail -n1 | xargs -r basename)
    fi

    if [ -z "$patch_file" ]; then
        echo -e "$name\tSKIPPED\tNo .patch files found in $pdir" >> "../$MANIFEST"
        if [ "$is_blocking" = "1" ]; then
            echo "ERROR BLOQUEANTE: No hay archivo de parche en '$name'." >&2
            exit 1
        fi
        return
    fi

    local patch_path="$pdir/$patch_file"
    echo "==> Evaluando $name ($patch_path)..."
    
    # Run a dry-run to capture exact failures
    if ! err_log=$(git apply --check -p1 --verbose "$patch_path" 2>&1); then
        # Failed to apply
        local reason="Conflict: $(echo "$err_log" | grep 'error:' | head -n 2 | tr '\n' ' ')"
        echo -e "$name\tSKIPPED\t$reason" >> "../$MANIFEST"
        
        if [ "$is_blocking" = "1" ]; then
            echo "" >&2
            echo "==========================================================" >&2
            echo "ERROR FATAL: El parche bloqueante '$name' falló en $DWL_VERSION." >&2
            echo "Log de git apply --check:" >&2
            echo "$err_log" >&2
            echo "==========================================================" >&2
            exit 1
        else
            echo "--> Advertencia: $name ($patch_file) falló. Detalle: $reason"
        fi
    else
        # Apply cleanly
        git apply "$patch_path"
        APPLIED="$APPLIED $name"
        echo -e "$name\tAPPLIED\tClean ($patch_file)" >> "../$MANIFEST"
        echo "--> Aplicado: $name"
    fi
}

echo "--> Aplicando parches bloqueantes..."
for name in $BLOCKING_PATCHES; do
    apply_patch_logic "$name" 1
done

echo "--> Aplicando parches QoL..."
for name in $QOL_PATCHES; do
    apply_patch_logic "$name" 0
done

echo "==> Construyendo manifest y tarball..."
rm -rf .git ../dwl-patches
cd "$WORKDIR/.."

mkdir -p dwl-devuan-0.9
cp -r "$WORKDIR/dwl"/* dwl-devuan-0.9/
cp "$MANIFEST" "dwl-devuan-0.9/PATCHES-APPLIED.txt"
tar czf dwl-devuan_0.9.orig.tar.gz dwl-devuan-0.9
rm -rf dwl-devuan-0.9

echo "==> Listo: dwl-devuan_0.9.orig.tar.gz generado exitosamente con Manifest."
