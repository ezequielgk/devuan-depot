#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script para generar AppImage de JDownloader2 (x86_64 y aarch64)
# v5: sin bucle de supervision. Todo vive en una carpeta contenedor
#     (~/.var/app/jdownloader2) y JD corre dentro de un sandbox bubblewrap.
#     El JRE vive en el contenedor para que el "Direct Restart" de JD no
#     dependa del mount temporal del AppImage.
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

# ==============================================================================
# Contenedor: TODO lo de JDownloader vive en una sola carpeta del host.
#   $CONTAINER/JDownloader2  -> jar, libs, cfg, logs, actualizaciones
#   $CONTAINER/jre           -> Java (copia fuera del mount del AppImage)
#
# Variables opcionales:
#   JD_CONTAINER_DIR  carpeta del contenedor  (def: ~/.var/app/jdownloader2)
#   JD_DOWNLOAD_DIR   carpeta de descargas    (def: ~/Downloads)
#   JD_EXTRA_BIND     otras carpetas con escritura, separadas por ':'
#   JD_SANDBOX=0      ejecutar sin sandbox (bubblewrap)
# ==============================================================================
CONTAINER="${JD_CONTAINER_DIR:-$HOME/.var/app/jdownloader2}"
APP_DIR="$CONTAINER/JDownloader2"
JRE_DIR="$CONTAINER/jre"
DOWNLOADS_DIR="${JD_DOWNLOAD_DIR:-$HOME/Downloads}"
LEGACY_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/JDownloader2"

mkdir -p "$CONTAINER" "$DOWNLOADS_DIR"

# --- Migracion unica desde la ubicacion anterior ------------------------------
if [ ! -e "$APP_DIR" ] && [ -f "$LEGACY_DIR/JDownloader.jar" ]; then
    echo "Migrando datos existentes de $LEGACY_DIR a $APP_DIR..."
    mv "$LEGACY_DIR" "$APP_DIR"
    if [ -d "$APP_DIR/jre" ] && [ ! -e "$JRE_DIR" ]; then
        mv "$APP_DIR/jre" "$JRE_DIR"
    fi
fi

# --- JDownloader.jar base (solo la primera vez) -------------------------------
mkdir -p "$APP_DIR"
if [ ! -f "$APP_DIR/JDownloader.jar" ]; then
    echo "Primera corrida: copiando JDownloader base en $APP_DIR..."
    cp -a "$HERE/opt/jdownloader/." "$APP_DIR/"
fi

# --- JRE persistente fuera del mount del AppImage -----------------------------
# JD hace un "Direct Restart" tras actualizarse: lanza un Java nuevo y cierra el
# actual. Si ese Java viviera en /tmp/.mount_*, desapareceria con el AppImage.
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

if [ ! -f "$APP_DIR/JDownloader.jar" ]; then
    echo "ERROR: no se encontro $APP_DIR/JDownloader.jar" >&2
    exit 1
fi

# Sin -Dsun.java2d.opengl=true: el pipeline OpenGL de Java2D es experimental y
# provoca "free(): invalid size" (abort de glibc) con Mesa/XWayland.
# --add-opens sun.awt.X11: permite a JD fijar su WM_CLASS (app-id e icono).
JAVA_OPTS_VALUE="-Dawt.useSystemAAFontSettings=on -Dswing.aatext=true --add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED"

# --- Sandbox (bubblewrap) ------------------------------------------------------
use_sandbox=0
if [ "${JD_SANDBOX:-1}" != "0" ]; then
    if command -v bwrap >/dev/null 2>&1 && bwrap --ro-bind / / --unshare-user-try true >/dev/null 2>&1; then
        use_sandbox=1
    else
        echo "AVISO: bubblewrap no esta disponible o no puede crear namespaces; se ejecuta SIN sandbox." >&2
    fi
fi

if [ "$use_sandbox" = "0" ]; then
    export JAVA_HOME="$JRE_DIR"
    export PATH="$JRE_DIR/bin:$PATH"
    export _JAVA_OPTIONS="$JAVA_OPTS_VALUE"
    cd "$APP_DIR"
    exec "$JRE_DIR/bin/java" -jar "$APP_DIR/JDownloader.jar" "$@"
fi

# Dentro del sandbox el HOME es el contenedor: JD solo ve su propia carpeta,
# las descargas y lo que se agregue en JD_EXTRA_BIND.
#
# Sin --unshare-pid ni --die-with-parent a proposito: el "Direct Restart" de JD
# lanza un Java nuevo y termina el viejo; con un namespace de PID el sandbox
# mataria al proceso nuevo, y --die-with-parent lo mataria si el lanzador sale.
args=(--unshare-user-try --unshare-uts --unshare-cgroup-try
      --ro-bind /usr /usr
      --ro-bind /etc /etc
      --proc /proc
      --dev /dev
      --tmpfs /tmp)

for d in /bin /sbin /lib /lib32 /lib64 /libx32; do
    if [ -L "$d" ]; then
        args+=(--symlink "$(readlink "$d")" "$d")
    elif [ -d "$d" ]; then
        args+=(--ro-bind "$d" "$d")
    fi
done

args+=(--ro-bind-try /tmp/.X11-unix /tmp/.X11-unix
       --ro-bind-try /run/systemd/resolve /run/systemd/resolve
       --ro-bind-try /run/NetworkManager /run/NetworkManager
       --bind "$CONTAINER" "$HOME"
       --bind "$DOWNLOADS_DIR" "$HOME/Downloads")

XA="${XAUTHORITY:-$HOME/.Xauthority}"
if [ -f "$XA" ]; then
    args+=(--ro-bind "$XA" "$XA")
fi

if [ -n "${JD_EXTRA_BIND:-}" ]; then
    IFS=':' read -ra extra <<< "$JD_EXTRA_BIND"
    for p in "${extra[@]}"; do
        if [ -d "$p" ]; then
            args+=(--bind "$p" "$p")
        else
            echo "AVISO: JD_EXTRA_BIND: '$p' no existe, se ignora." >&2
        fi
    done
fi

exec bwrap "${args[@]}" \
    --chdir "$HOME/JDownloader2" \
    --setenv HOME "$HOME" \
    --setenv JAVA_HOME "$HOME/jre" \
    --setenv PATH "$HOME/jre/bin:/usr/local/bin:/usr/bin:/bin" \
    --setenv _JAVA_OPTIONS "$JAVA_OPTS_VALUE" \
    "$HOME/jre/bin/java" -jar "$HOME/JDownloader2/JDownloader.jar" "$@"
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
