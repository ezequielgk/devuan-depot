#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script para generar AppImage de JDownloader2 (x86_64 y aarch64)
# v3: sin bucle de supervision. El JRE se copia a ~/.local/share/JDownloader2/jre
#     para que el "Direct Restart" de JD no dependa del mount temporal del AppImage.
# ==============================================================================

# 1. Verificacion de dependencias criticas de BUILD
for cmd in curl jq tar unzip; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: La dependencia de build '$cmd' no esta instalada en el sistema." >&2
        exit 1
    fi
done

ORIGDIR="$(pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

# 2. Deteccion dinamica de arquitectura
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
  echo "ERROR: Adoptium no devolvio un enlace para el JRE 17 de Linux (${ADOPTIUM_ARCH})" >&2
  exit 1
fi

curl --fail --silent --show-error --location --retry 3 --retry-all-errors "$JRE_URL" --output jre.tar.gz
tar -xzf jre.tar.gz -C "$APPDIR/opt/jre" --strip-components=1

if [[ ! -x "$APPDIR/opt/jre/bin/java" ]]; then
    echo "ERROR: El JRE no quedo instalado correctamente." >&2
    exit 1
fi

# Identificador de version del JRE: el AppRun lo usa para saber cuando
# hay que refrescar la copia que vive en el home del usuario.
basename "$JRE_URL" > "$APPDIR/opt/.jre-version"
echo "✅ JRE extraido correctamente ($(cat "$APPDIR/opt/.jre-version"))"

# ==============================================================================
# 4. Descarga directa de JDownloader.jar
# ==============================================================================
echo "=== Descargando JDownloader.jar base ==="
curl --fail --silent --show-error --location --retry 3 --retry-all-errors \
  "https://installer.jdownloader.org/JDownloader.jar" \
  --output "$APPDIR/opt/jdownloader/JDownloader.jar"

if ! unzip -tq "$APPDIR/opt/jdownloader/JDownloader.jar" >/dev/null 2>&1; then
    echo "ERROR: El archivo descargado no es un JAR valido (posible pagina de error HTML o fallo de red)." >&2
    exit 1
fi
echo "✅ JDownloader.jar descargado y verificado correctamente"

# ==============================================================================
# 5. Extraccion del icono (con fallback)
# ==============================================================================
echo "=== Extrayendo icono ==="
ICON="$APPDIR/jdownloader.png"
for p in \
  "org/jdownloader/images/logo/jd_logo_256_256.png" \
  "themes/standard/org/jdownloader/images/updatericon.png"; do
    unzip -p "$APPDIR/opt/jdownloader/JDownloader.jar" "$p" > "$ICON" 2>/dev/null || true
    [[ -s "$ICON" ]] && break
done

if [[ ! -s "$ICON" ]]; then
    echo "Usando fallback de icono desde Wikimedia..."
    curl --fail --silent --show-error --location \
      "https://upload.wikimedia.org/wikipedia/commons/4/43/Jdownloader.png" -o "$ICON" || true

    if [[ ! -s "$ICON" ]]; then
        echo "ERROR: No se pudo obtener el icono por ningun medio." >&2
        exit 1
    fi
fi

# ==============================================================================
# 6. Archivos de configuracion del AppDir
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

echo "=== Creando script AppRun wrapper ==="
# 'INNER_EOF_RUN' entre comillas simples: las variables se evaluan al ejecutar
# el AppImage, no ahora.
cat << 'INNER_EOF_RUN' > "$APPDIR/AppRun"
#!/bin/bash
set -e

HERE="$(dirname "$(readlink -f "$0")")"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/JDownloader2"
JRE_DIR="$DATA_DIR/jre"

mkdir -p "$DATA_DIR"

# --- JDownloader.jar base (solo la primera vez) -------------------------------
if [ ! -f "$DATA_DIR/JDownloader.jar" ]; then
    echo "Primera corrida: copiando JDownloader base en $DATA_DIR..."
    cp -a "$HERE/opt/jdownloader/." "$DATA_DIR/"
fi

# --- JRE persistente fuera del mount del AppImage -----------------------------
# JD hace un "Direct Restart" tras actualizarse: lanza un Java nuevo y cierra el
# actual. Si ese Java viviera en /tmp/.mount_*, desapareceria junto con el
# proceso original. Por eso usamos una copia del JRE en el home del usuario.
WANT_VER="$(cat "$HERE/opt/.jre-version")"
HAVE_VER="$(cat "$JRE_DIR/.jre-version" 2>/dev/null || true)"

if [ ! -x "$JRE_DIR/bin/java" ] || [ "$WANT_VER" != "$HAVE_VER" ]; then
    echo "Preparando entorno Java en $JRE_DIR..."
    rm -rf "$JRE_DIR.tmp"
    cp -a "$HERE/opt/jre" "$JRE_DIR.tmp"
    cp "$HERE/opt/.jre-version" "$JRE_DIR.tmp/.jre-version"
    rm -rf "$JRE_DIR"
    mv "$JRE_DIR.tmp" "$JRE_DIR"
fi

if [ ! -f "$DATA_DIR/JDownloader.jar" ]; then
    echo "ERROR: no se encontro $DATA_DIR/JDownloader.jar" >&2
    exit 1
fi

export JAVA_HOME="$JRE_DIR"
export PATH="$JRE_DIR/bin:$PATH"
export _JAVA_OPTIONS="-Dawt.useSystemAAFontSettings=on -Dswing.aatext=true -Dsun.java2d.opengl=true"

cd "$DATA_DIR"

# exec: sin bucle. Si JD se reinicia solo, el proceso nuevo ya no depende del
# mount; si el usuario cierra JD, se cierra todo.
exec "$JRE_DIR/bin/java" -jar "$DATA_DIR/JDownloader.jar" "$@"
INNER_EOF_RUN

chmod +x "$APPDIR/AppRun"

# ==============================================================================
# 7. Empaquetado en AppImage
# ==============================================================================
echo "=== Descargando appimagetool para ${APPIMAGE_ARCH} ==="
curl --fail --silent --show-error --location --retry 3 --retry-all-errors \
  "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${APPIMAGE_ARCH}.AppImage" \
  -o appimagetool.AppImage

chmod +x appimagetool.AppImage

export ARCH="$APPIMAGE_ARCH"
OUTPUT_NAME="JDownloader2-${APPIMAGE_ARCH}.AppImage"

echo "=== Generando AppImage: $OUTPUT_NAME ==="
./appimagetool.AppImage --appimage-extract-and-run "$APPDIR" "$OUTPUT_NAME"

test -s "$OUTPUT_NAME" || { echo "ERROR: no se genero el AppImage" >&2; exit 1; }

# ==============================================================================
# 8. Verificacion del AppImage generado (falla el build si esta incompleto)
# ==============================================================================
echo "=== Verificando contenido del AppImage ==="
chmod +x "$OUTPUT_NAME"
mkdir -p verify && ( cd verify && "../$OUTPUT_NAME" --appimage-extract >/dev/null )
CHK="verify/squashfs-root"

for f in AppRun jdownloader.desktop jdownloader.png \
         opt/jdownloader/JDownloader.jar opt/jre/bin/java opt/.jre-version; do
    if [[ ! -s "$CHK/$f" ]]; then
        echo "ERROR: el AppImage generado no contiene '$f'" >&2
        exit 1
    fi
done
unzip -tq "$CHK/opt/jdownloader/JDownloader.jar" >/dev/null \
    || { echo "ERROR: JDownloader.jar dentro del AppImage esta corrupto" >&2; exit 1; }
"$CHK/opt/jre/bin/java" -version >/dev/null 2>&1 \
    || { echo "ERROR: el JRE incluido no se puede ejecutar" >&2; exit 1; }
bash -n "$CHK/AppRun" \
    || { echo "ERROR: el AppRun tiene errores de sintaxis" >&2; exit 1; }
echo "✅ Verificacion OK"

cp "$OUTPUT_NAME" "$ORIGDIR/"
echo "=== ✅ Generado correctamente: $ORIGDIR/$OUTPUT_NAME ==="
