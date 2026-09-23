#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

echo "=== Creando estructura del AppDir ==="
APPDIR="${WORKDIR}/AppDir"
mkdir -p "$APPDIR/opt/jdownloader"

echo "=== Descargando JDownloader.jar (Updater oficial) ==="
curl -sL "https://installer.jdownloader.org/JDownloader.jar" -o "$APPDIR/opt/jdownloader/JDownloader.jar"

echo "=== Extrayendo icono para el AppImage ==="
unzip -p "$APPDIR/opt/jdownloader/JDownloader.jar" "themes/standard/org/jdownloader/images/updatericon.png" > "$APPDIR/jdownloader.png" || true
if [ ! -s "$APPDIR/jdownloader.png" ]; then
    echo "Descargando icono alternativo..."
    curl -sL "https://upload.wikimedia.org/wikipedia/commons/4/43/Jdownloader.png" -o "$APPDIR/jdownloader.png"
fi

echo "=== Descargando entorno Java (OpenJDK JRE 17) ==="
JRE_URL=$(curl -sL "https://api.github.com/repos/adoptium/temurin17-binaries/releases/latest" \
  | jq -r '.assets[] | select(.name | test("jre_linux_x64_linux_hotspot_.*\\.tar\\.gz$")) | .browser_download_url' | head -1)

if [ -z "$JRE_URL" ]; then
    echo "ERROR: no se pudo obtener link al JRE"
    exit 1
fi
echo "JRE URL: ${JRE_URL}"
curl -sL "$JRE_URL" -o jre.tar.gz

mkdir -p "$APPDIR/opt/jre"
tar -xzf jre.tar.gz -C "$APPDIR/opt/jre" --strip-components=1

echo "=== Creando jdownloader.desktop ==="
cat << 'INNER_EOF' > "$APPDIR/jdownloader.desktop"
[Desktop Entry]
Name=JDownloader2
Comment=Download Manager
Exec=AppRun %U
Terminal=false
Type=Application
Icon=jdownloader
Categories=Network;FileTransfer;
StartupNotify=true
INNER_EOF

echo "=== Creando script AppRun wrapper (PORTABLE) ==="
cat << 'INNER_EOF_RUN' > "$APPDIR/AppRun"
#!/bin/bash
export HERE="$(dirname "$(readlink -f "$0")")"
export PATH="$HERE/opt/jre/bin:$PATH"
export _JAVA_OPTIONS="-Dawt.useSystemAAFontSettings=on -Dswing.aatext=true -Dsun.java2d.opengl=true"

DATA_DIR="$HOME/.local/share/JDownloader2"
mkdir -p "$DATA_DIR"

if [ ! -f "$DATA_DIR/JDownloader.jar" ]; then
    cp "$HERE/opt/jdownloader/JDownloader.jar" "$DATA_DIR/"
fi

cd "$DATA_DIR"
exec java -jar "$DATA_DIR/JDownloader.jar" "$@"
INNER_EOF_RUN
chmod +x "$APPDIR/AppRun"

echo "=== Empaquetando ==="
curl -sL -o appimagetool "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
chmod +x appimagetool

export ARCH=x86_64
./appimagetool --appimage-extract-and-run "$APPDIR" "JDownloader2-x86_64.AppImage"

cp "JDownloader2-x86_64.AppImage" "${OLDPWD:-.}/"
echo "=== Generado correctamente ==="
