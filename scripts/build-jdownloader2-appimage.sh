#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script para generar AppImage de JDownloader2 (x86_64 y aarch64)
# Versión endurecida: con AppRun de bucle para soportar el "Direct Restart" de JD
# ==============================================================================

# 1. Verificación de dependencias críticas de BUILD
for cmd in curl jq tar unzip; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: La dependencia de build '$cmd' no está instalada en el sistema." >&2
        exit 1
    fi
done

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

# 2. Detección dinámica de arquitectura
echo "=== Detectando arquitectura del sistema ==="
case "$(uname -m)" in
  x86_64)  
    ADOPTIUM_ARCH="x64"
    APPIMAGE_ARCH="x86_64"
    ;;
  aarch64) 
    ADOPTIUM_ARCH="aarch64"
    APPIMAGE_ARCH="aarch64"
    ;;
  *) 
    echo "ERROR: Arquitectura no soportada: $(uname -m)" >&2
    exit 1
    ;;
esac
echo "Arquitectura: $(uname -m) (Adoptium: $ADOPTIUM_ARCH, AppImage: $APPIMAGE_ARCH)"

APPDIR="${WORKDIR}/AppDir"
mkdir -p "$APPDIR/opt/jdownloader"
mkdir -p "$APPDIR/opt/jre"

# ==============================================================================
# 3. Descarga del entorno Java (OpenJDK JRE 17) desde Adoptium
# ==============================================================================
echo "=== Descargando entorno Java (OpenJDK JRE 17) ==="
JRE_API_URL="https://api.adoptium.net/v3/assets/latest/17/hotspot"

API_RESPONSE="$(curl --fail --silent --show-error --location --retry 3 "${JRE_API_URL}?architecture=${ADOPTIUM_ARCH}&image_type=jre&os=linux&vendor=eclipse")"
JRE_URL="$(jq -r '.[0].binary.package.link // empty' <<< "$API_RESPONSE")"

if [[ -z "$JRE_URL" || "$JRE_URL" == "null" ]]; then
  echo "ERROR: Adoptium no devolvió un enlace para el JRE 17 de Linux (${ADOPTIUM_ARCH})" >&2
  exit 1
fi

curl --fail --silent --show-error --location --retry 3 --retry-all-errors "$JRE_URL" --output jre.tar.gz
tar -xzf jre.tar.gz -C "$APPDIR/opt/jre" --strip-components=1
echo "✅ JRE extraído correctamente"

# ==============================================================================
# 4. Descarga directa de JDownloader.jar (Sin instalador, sin || true)
# ==============================================================================
echo "=== Descargando JDownloader.jar base ==="
curl --fail --silent --show-error --location --retry 3 --retry-all-errors \
  "https://installer.jdownloader.org/JDownloader.jar" \
  --output "$APPDIR/opt/jdownloader/JDownloader.jar"

# Verificación estricta: asegurar que sea un JAR válido y no una página de error HTML
if ! unzip -tq "$APPDIR/opt/jdownloader/JDownloader.jar" >/dev/null 2>&1; then
    echo "ERROR: El archivo descargado no es un JAR válido (posible página de error HTML o fallo de red)." >&2
    exit 1
fi
echo "✅ JDownloader.jar descargado y verificado correctamente"

# ==============================================================================
# 5. Extracción del icono (Con fallback infalible)
# ==============================================================================
echo "=== Extrayendo icono ==="
unzip -p "$APPDIR/opt/jdownloader/JDownloader.jar" "org/jdownloader/images/logo/jd_logo_256_256.png" > "$APPDIR/jdownloader.png" 2>/dev/null || \
unzip -p "$APPDIR/opt/jdownloader/JDownloader.jar" "themes/standard/org/jdownloader/images/updatericon.png" > "$APPDIR/jdownloader.png" 2>/dev/null || true

if [[ ! -s "$APPDIR/jdownloader.png" ]]; then
    echo "Usando fallback de icono desde Wikimedia..."
    curl --fail --silent --show-error --location "https://upload.wikimedia.org/wikipedia/commons/4/43/Jdownloader.png" -o "$APPDIR/jdownloader.png"
    
    if [[ ! -s "$APPDIR/jdownloader.png" ]]; then
        echo "ERROR: No se pudo obtener el icono por ningún medio." >&2
        exit 1
    fi
fi

# ==============================================================================
# 6. Creación de archivos de configuración del AppDir
# ==============================================================================
echo "=== Creando jdownloader.desktop ==="
cat << 'INNER_EOF' > "$APPDIR/jdownloader.desktop"
[Desktop Entry]
Name=JDownloader 2
Comment=Download Manager
Exec=AppRun %U
Terminal=false
Type=Application
Icon=jdownloader
Categories=Network;FileTransfer;
StartupNotify=true
MimeType=x-scheme-handler/jd;
INNER_EOF

echo "=== Creando script AppRun wrapper (PORTABLE) ==="
# NOTA: Usamos 'INNER_EOF_RUN' con comillas simples para que las variables ($HERE, etc.)
# NO se evalúen ahora, sino en tiempo de ejecución cuando el usuario lance el AppImage.
cat << 'INNER_EOF_RUN' > "$APPDIR/AppRun"
#!/bin/bash

export HERE="$(dirname "$(readlink -f "$0")")"
export PATH="$HERE/opt/jre/bin:$PATH"
export _JAVA_OPTIONS="-Dawt.useSystemAAFontSettings=on -Dswing.aatext=true -Dsun.java2d.opengl=true"

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/JDownloader2"
mkdir -p "$DATA_DIR"

if [ ! -f "$DATA_DIR/JDownloader.jar" ]; then
    echo "Primera corrida: copiando JDownloader base en $DATA_DIR..."
    cp -a "$HERE/opt/jdownloader/." "$DATA_DIR/"
fi

cd "$DATA_DIR"

# Capturar señales (Ctrl+C) para salir limpiamente
trap 'echo "Cerrando JDownloader..."; exit 0' INT TERM

# BUCLE DE SUPERVISIÓN:
# JDownloader realiza un "Direct Restart" interno tras la primera actualización.
# Si usáramos 'exec java', el proceso principal del AppImage moriría al reiniciar,
# desmontando el sistema de archivos temporal (/tmp/.mount_...) y matando al 
# proceso hijo que intentaba arrancar.
# Mantener el script bash vivo con un bucle while preserva el mount point.
while true; do
    java -jar "$DATA_DIR/JDownloader.jar" "$@"
    
    # Pausa breve para evitar bucles frenéticos en caso de error fatal de Java
    sleep 2
done
INNER_EOF_RUN

chmod +x "$APPDIR/AppRun"

# ==============================================================================
# 7. Empaquetado en AppImage
# ==============================================================================
echo "=== Descargando appimagetool para ${APPIMAGE_ARCH} ==="
curl --fail --silent --show-error --location \
  "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${APPIMAGE_ARCH}.AppImage" \
  -o appimagetool.AppImage

chmod +x appimagetool.AppImage

export ARCH="$APPIMAGE_ARCH"
OUTPUT_NAME="JDownloader2-${APPIMAGE_ARCH}.AppImage"

echo "=== Generando AppImage: $OUTPUT_NAME ==="
./appimagetool.AppImage --appimage-extract-and-run "$APPDIR" "$OUTPUT_NAME"

cp "$OUTPUT_NAME" "${OLDPWD:-.}/"
echo "=== ✅ Generado correctamente: ${OLDPWD:-.}/$OUTPUT_NAME ==="
