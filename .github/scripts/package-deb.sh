#!/usr/bin/env bash
set -e

# Toma ./AppDir (generado por build-steam-bundle.sh) y arma un .deb
# autocontenido en /opt/steam-bundled, sin depender de libs del sistema.

ARCH_DEB="${ARCH_DEB:-amd64}"          # arquitectura Debian (dpkg usa amd64, no x86_64)
VERSION="$(cat ~/version 2>/dev/null || echo "0.0.0").${GITHUB_RUN_NUMBER:-0}~devuandepot"
PKGNAME="steam-bundled"
BUILD_DIR="./deb-build"
INSTALL_PREFIX="opt/${PKGNAME}"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/DEBIAN"
mkdir -p "$BUILD_DIR/$INSTALL_PREFIX"
mkdir -p "$BUILD_DIR/usr/bin"
mkdir -p "$BUILD_DIR/usr/share/applications"
mkdir -p "$BUILD_DIR/usr/share/icons/hicolor/256x256/apps"

echo "== copiando AppDir a $BUILD_DIR/$INSTALL_PREFIX"
cp -a ./AppDir/. "$BUILD_DIR/$INSTALL_PREFIX/"

echo "== creando wrapper de lanzamiento"
cat <<EOF > "$BUILD_DIR/usr/bin/${PKGNAME}"
#!/usr/bin/env bash
exec "/${INSTALL_PREFIX}/AppRun" "\$@"
EOF
chmod 755 "$BUILD_DIR/usr/bin/${PKGNAME}"

echo "== copiando icono y .desktop"
cp ./AppDir/../steam.png "$BUILD_DIR/usr/share/icons/hicolor/256x256/apps/${PKGNAME}.png" 2>/dev/null \
	|| cp ~/steam.png "$BUILD_DIR/usr/share/icons/hicolor/256x256/apps/${PKGNAME}.png"

cat <<EOF > "$BUILD_DIR/usr/share/applications/${PKGNAME}.desktop"
[Desktop Entry]
Name=Steam (Bundled)
Comment=Application for managing and playing games on Steam (self-contained bundle)
Exec=${PKGNAME} %U
Icon=${PKGNAME}
Terminal=false
Type=Application
Categories=Network;FileTransfer;Game;
MimeType=x-scheme-handler/steam;
StartupWMClass=steam
EOF

echo "== escribiendo control file"
INSTALLED_SIZE=$(du -sk "$BUILD_DIR/$INSTALL_PREFIX" | cut -f1)

cat <<EOF > "$BUILD_DIR/DEBIAN/control"
Package: ${PKGNAME}
Version: ${VERSION}
Section: games
Priority: optional
Architecture: ${ARCH_DEB}
Installed-Size: ${INSTALLED_SIZE}
Maintainer: $(git config user.name 2>/dev/null || echo "Rox") <$(git config user.email 2>/dev/null || echo "noreply@example.com")>
Description: Steam (self-contained bundle)
 Steam empaquetado como bundle autocontenido (libs propias vía
 RunImage/pacman), sin depender de las librerías del sistema.
 No requiere multiarch (i386) en el host: todo lo necesario
 para correr juegos de 32/64 bits viene incluido en el bundle.
EOF

echo "== postinst / prerm (cache de iconos y desktop database)"
cat <<'EOF' > "$BUILD_DIR/DEBIAN/postinst"
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
	update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
	gtk-update-icon-cache -q /usr/share/icons/hicolor || true
fi
exit 0
EOF
chmod 755 "$BUILD_DIR/DEBIAN/postinst"

cat <<'EOF' > "$BUILD_DIR/DEBIAN/prerm"
#!/bin/sh
set -e
exit 0
EOF
chmod 755 "$BUILD_DIR/DEBIAN/prerm"

echo "== build .deb"
OUTFILE="${PKGNAME}_${VERSION}_${ARCH_DEB}.deb"
dpkg-deb --root-owner-group --build "$BUILD_DIR" "$OUTFILE"

echo "Listo: $OUTFILE"
