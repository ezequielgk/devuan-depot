#!/usr/bin/env bash
# scripts/build-opentabletdriver-appimage.sh
#
# Empaqueta OpenTabletDriver como AppImage a partir del .deb oficial que
# el proyecto ya publica en sus Releases de GitHub. No compilamos nada:
# extraemos los binarios ya construidos (evita depender del SDK de .NET
# completo en el pipeline) y los envolvemos con linuxdeploy + appimagetool.
#
# Uso:
#   GITHUB_TOKEN=xxx ./scripts/build-opentabletdriver-appimage.sh
#
# Salida: OpenTabletDriver-<version>-x86_64.AppImage en el directorio actual.

set -euo pipefail

REPO="OpenTabletDriver/OpenTabletDriver"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

echo "=== Consultando el ultimo release de ${REPO} ==="
AUTH_HEADER=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
    AUTH_HEADER=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi
RELEASE_JSON=$(curl -sL "${AUTH_HEADER[@]}" "https://api.github.com/repos/${REPO}/releases/latest")

VERSION=$(echo "$RELEASE_JSON" | jq -r '.tag_name' | sed 's/^v//')
DEB_URL=$(echo "$RELEASE_JSON" | jq -r '.assets[] | select(.name | test("x64\\.deb$")) | .browser_download_url' | head -1)

if [ -z "$DEB_URL" ] || [ "$DEB_URL" = "null" ]; then
    echo "ERROR: no se encontro un asset .deb x64 en el ultimo release de ${REPO}"
    echo "Assets disponibles:"
    echo "$RELEASE_JSON" | jq -r '.assets[].name'
    exit 1
fi
echo "Version: ${VERSION}"
echo "Deb oficial: ${DEB_URL}"

echo "=== Descargando .deb oficial ==="
curl -sL "$DEB_URL" -o otd.deb

echo "=== Extrayendo contenido del .deb ==="
mkdir -p extracted
dpkg-deb -x otd.deb extracted

echo "=== Ubicando el .desktop file ==="
DESKTOP_FILE=$(find extracted/usr/share/applications -name '*.desktop' 2>/dev/null | head -1)
if [ -z "$DESKTOP_FILE" ]; then
    echo "ERROR: no se encontro ningun .desktop dentro del .deb -- revisar estructura"
    find extracted -maxdepth 4
    exit 1
fi
echo "Desktop file: ${DESKTOP_FILE}"

EXEC_LINE=$(grep -m1 '^Exec=' "$DESKTOP_FILE" | cut -d= -f2- | sed 's/ %[a-zA-Z]//g')
EXEC_BIN=$(echo "$EXEC_LINE" | awk '{print $1}')
if [ -z "$EXEC_BIN" ]; then
    echo "ERROR: no se pudo parsear el campo Exec= del .desktop"
    cat "$DESKTOP_FILE"
    exit 1
fi
echo "Ejecutable principal detectado: ${EXEC_BIN}"

# Resolver ruta absoluta del binario dentro de lo extraido
EXEC_PATH="extracted${EXEC_BIN}"
if [ ! -f "$EXEC_PATH" ]; then
    EXEC_PATH=$(find extracted/usr/bin -iname "$(basename "$EXEC_BIN")" | head -1)
fi
if [ -z "$EXEC_PATH" ] || [ ! -f "$EXEC_PATH" ]; then
    echo "ERROR: no se pudo ubicar el binario ejecutable '${EXEC_BIN}' dentro del .deb"
    exit 1
fi
echo "Binario resuelto: ${EXEC_PATH}"
# Ruta relativa a la raiz del AppDir (usada en AppRun, no puede ser absoluta
# porque en runtime el AppImage se monta en un path distinto al de build)
REL_EXEC="${EXEC_PATH#extracted/}"

echo "=== Detectando runtime de .NET requerido ==="
# El .deb oficial es framework-dependent: declara un Depends hacia un
# dotnet-runtime-X.Y o aspnetcore-runtime-X.Y especifico que NO existe
# en los repos de Debian/Devuan. Si no lo empaquetamos nosotros mismos
# adentro del AppImage, el binario falla al no encontrar libhostfxr.so
# en runtime.
DEPENDS=$(dpkg-deb -f otd.deb Depends)
echo "Depends declarados por el .deb: ${DEPENDS}"

RUNTIME_KIND=""
RUNTIME_CHANNEL=""
if echo "$DEPENDS" | grep -qoP 'aspnetcore-runtime-\K[0-9]+\.[0-9]+'; then
    RUNTIME_KIND="aspnetcore"
    RUNTIME_CHANNEL=$(echo "$DEPENDS" | grep -oP 'aspnetcore-runtime-\K[0-9]+\.[0-9]+' | head -1)
elif echo "$DEPENDS" | grep -qoP 'dotnet-runtime-\K[0-9]+\.[0-9]+'; then
    RUNTIME_KIND="dotnet"
    RUNTIME_CHANNEL=$(echo "$DEPENDS" | grep -oP 'dotnet-runtime-\K[0-9]+\.[0-9]+' | head -1)
fi

if [ -z "$RUNTIME_KIND" ] || [ -z "$RUNTIME_CHANNEL" ]; then
    echo "ERROR: no se pudo detectar la version de runtime .NET requerida"
    echo "desde el campo Depends del .deb. Revisar manualmente:"
    echo "$DEPENDS"
    exit 1
fi
echo "Runtime requerido: ${RUNTIME_KIND} ${RUNTIME_CHANNEL}"

echo "=== Instalando runtime .NET ${RUNTIME_CHANNEL} (self-contained, sin tocar el sistema) ==="
curl -sSL https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh
chmod +x dotnet-install.sh
mkdir -p dotnet-runtime
./dotnet-install.sh --channel "$RUNTIME_CHANNEL" --runtime "$RUNTIME_KIND" --install-dir dotnet-runtime

# Eliminar el provider de tracing de LTTng porque depende de liblttng-ust.so.0
# (una libreria vieja que linuxdeploy no encuentra y hace abortar el build).
# El runtime de .NET funciona perfectamente sin esto, solo se deshabilita el tracing.
rm -f dotnet-runtime/shared/Microsoft.NETCore.App/*/libcoreclrtraceptprovider.so

echo "=== Armando AppDir ==="
APPDIR="${WORKDIR}/AppDir"
mkdir -p "$APPDIR"
cp -a extracted/usr "$APPDIR/usr"
mkdir -p "$APPDIR/usr/lib/dotnet"
cp -a dotnet-runtime/. "$APPDIR/usr/lib/dotnet/"

echo "=== Descargando linuxdeploy y appimagetool ==="
curl -sL -o linuxdeploy https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
curl -sL -o appimagetool https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x linuxdeploy appimagetool

# linuxdeploy resuelve el AppRun, bundlea librerias no-base y coloca
# desktop/icono en la raiz del AppDir a partir de lo que ya trae el .deb
DESKTOP_ARG=(--desktop-file "$DESKTOP_FILE")
ICON_NAME=$(grep -m1 '^Icon=' "$DESKTOP_FILE" | cut -d= -f2- || true)
ICON_ARG=()
if [ -n "$ICON_NAME" ]; then
    ICON_BASENAME=$(basename "$ICON_NAME")
    ICON_FILE=$(find extracted/usr/share/icons extracted/usr/share/pixmaps -iname "${ICON_BASENAME}*" 2>/dev/null | head -1 || true)
    if [ -n "$ICON_FILE" ]; then
        ICON_ARG=(--icon-file "$ICON_FILE")
    else
        echo "ADVERTENCIA: no se encontro el archivo del icono '${ICON_NAME}'"
    fi
else
    echo "ADVERTENCIA: no se encontro icono declarado en el .desktop, linuxdeploy usara uno generico"
fi

echo "=== Empaquetando con linuxdeploy (bundlea libs faltantes del sistema) ==="
./linuxdeploy --appimage-extract-and-run \
    --appdir "$APPDIR" \
    "${DESKTOP_ARG[@]}" \
    "${ICON_ARG[@]}"

# linuxdeploy genera su propio AppRun, pero necesitamos uno custom que:
#  - exporte DOTNET_ROOT apuntando al runtime que bundleamos
#  - arranque OpenTabletDriver.Daemon en background antes de la GUI
#  - limpie sockets viejos en /tmp que quedan si el daemon no cerro bien
#    (bug conocido: https://github.com/OpenTabletDriver/OpenTabletDriver/issues/3804)
#  - mate el daemon cuando la GUI se cierra, para no dejarlo huerfano
DAEMON_REL=$(find extracted/usr/bin -iname 'OpenTabletDriver.Daemon' | head -1)
DAEMON_REL="${DAEMON_REL#extracted/}"
if [ -z "$DAEMON_REL" ]; then
    echo "ADVERTENCIA: no se encontro OpenTabletDriver.Daemon -- el AppRun no lo va a arrancar automaticamente"
fi

cat > "$APPDIR/AppRun" <<APPRUN
#!/bin/sh
HERE="\$(dirname "\$(readlink -f "\$0")")"
export DOTNET_ROOT="\$HERE/usr/lib/dotnet"
export PATH="\$DOTNET_ROOT:\$HERE/usr/bin:\$PATH"
export LD_LIBRARY_PATH="\$HERE/usr/lib:\$HERE/usr/lib/x86_64-linux-gnu:\$LD_LIBRARY_PATH"

# Limpiar socket viejo si quedo de una sesion anterior sin cerrar bien
rm -f /tmp/CoreFxPipe_OpenTabletDriver.Daemon 2>/dev/null || true

DAEMON_PID=""
if [ -n "${DAEMON_REL}" ]; then
    "\$HERE/${DAEMON_REL}" &
    DAEMON_PID=\$!
    # Pequeña espera para que el daemon levante el socket antes de la GUI
    sleep 1
fi

cleanup() {
    [ -n "\$DAEMON_PID" ] && kill "\$DAEMON_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

exec "\$HERE/${REL_EXEC}" "\$@"
APPRUN
chmod +x "$APPDIR/AppRun"

echo "=== Generando el AppImage final ==="
./appimagetool --appimage-extract-and-run "$APPDIR" "OpenTabletDriver-${VERSION}-x86_64.AppImage"

cp "OpenTabletDriver-${VERSION}-x86_64.AppImage" "${OLDPWD:-.}/"
echo "VERSION=${VERSION}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
echo "=== Listo: OpenTabletDriver-${VERSION}-x86_64.AppImage ==="
