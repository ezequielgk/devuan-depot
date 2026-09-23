#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

echo "=== Creando estructura del AppDir ==="
APPDIR="${WORKDIR}/AppDir"
mkdir -p "$APPDIR/opt/jdownloader"

# Pre-instalando entorno de JDownloader2 en la nube (Para que el usuario no tenga que lidiar con
# descargar 100MB en su primera corrida ni sufrir errores de TLS con el servidor viejo)

echo "=== Descargando entorno Java (OpenJDK JRE 17) ==="
# Consultar API oficial de Adoptium para obtener el link de descarga exacto
JRE_API_URL="https://api.adoptium.net/v3/assets/latest/17/hotspot"

# Identificar arquitectura real
case "$(uname -m)" in
  x86_64)  ADOPTIUM_ARCH=x64 ;;
  aarch64) ADOPTIUM_ARCH=aarch64 ;;
  *) echo "ERROR: Arquitectura no soportada: $(uname -m)" >&2; exit 1 ;;
esac

echo "Consultando API para ${ADOPTIUM_ARCH}..."
API_RESPONSE="$(curl --fail --silent --show-error --location --retry 3 "${JRE_API_URL}?architecture=${ADOPTIUM_ARCH}&image_type=jre&os=linux&vendor=eclipse")"

JRE_URL="$(jq -r '.[0].binary.package.link // empty' <<< "$API_RESPONSE")"

if [[ -z "$JRE_URL" || "$JRE_URL" == "null" ]]; then
  echo "ERROR: Adoptium no devolvio un enlace para el JRE 17 x64 de Linux" >&2
  echo "==== API RESPONSE DEBUG ===="
  echo "$API_RESPONSE" | jq '.' >&2
  exit 1
fi
echo "JRE URL: ${JRE_URL}"

curl --fail --silent --show-error --location --retry 3 --retry-all-errors "$JRE_URL" --output jre.tar.gz

mkdir -p "$APPDIR/opt/jre"
tar -xzf jre.tar.gz -C "$APPDIR/opt/jre" --strip-components=1

echo "=== Bootstrap de librerias completas usando el instalador oficial ==="
curl -sSL "https://installer.jdownloader.org/JD2Setup_x64.sh" -o setup.sh
# El instalador detectara el java del path o lo traera internamente, logramos un setup silencioso
sh setup.sh -q -dir "$APPDIR/opt/jdownloader" || true
rm -f setup.sh
# Limpieza de exceso del instalador (basura, jre propietario, uninstaller)
rm -rf "$APPDIR/opt/jdownloader/java" "$APPDIR/opt/jdownloader/jre" "$APPDIR/opt/jdownloader/Uninstall"*


echo "=== Extrayendo icono AHORA que ya tenemos los themes (Fallback si updatericon no esta) ==="
unzip -p "$APPDIR/opt/jdownloader/JDownloader.jar" "themes/standard/org/jdownloader/images/updatericon.png" > "$APPDIR/jdownloader.png" || true
if [ ! -s "$APPDIR/jdownloader.png" ]; then
    cp "$APPDIR/opt/jdownloader/themes/standard/org/jdownloader/images/logo/jd_logo_256_256.png" "$APPDIR/jdownloader.png" 2>/dev/null || \
    curl -sL "https://upload.wikimedia.org/wikipedia/commons/4/43/Jdownloader.png" -o "$APPDIR/jdownloader.png"
fi

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
    echo "Primera corrida: copiando bibliotecas pre-compiladas de JDownloader en $DATA_DIR..."
    cp -rn "$HERE/opt/jdownloader/"* "$DATA_DIR/"
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
