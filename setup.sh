#!/usr/bin/env bash
# setup-rox-apt-repo.sh
# Crea la estructura inicial del repo APT personal (workflows + gh-pages).
# Uso: ./setup-rox-apt-repo.sh [nombre-del-repo]

set -euo pipefail

REPO_NAME="${1:-rox-apt-repo}"

echo "==> Creando estructura en ./${REPO_NAME}"
mkdir -p "${REPO_NAME}"
cd "${REPO_NAME}"

# --- Rama principal: solo workflows + docs ---
mkdir -p .github/workflows

cat > README.md <<'EOF'
# rox-apt-repo

Repositorio APT personal. Los workflows en `.github/workflows/` compilan
proyectos (propios o de terceros) y publican los `.deb` resultantes en la
rama `gh-pages`, que se sirve vía GitHub Pages como repositorio APT.

## Instalación (en Devuan/Debian)

```bash
curl -fsSL https://TU_USUARIO.github.io/REPO_NAME/public.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/rox-apt-repo.gpg

echo "deb [signed-by=/usr/share/keyrings/rox-apt-repo.gpg] https://TU_USUARIO.github.io/REPO_NAME trixie main" \
  | sudo tee /etc/apt/sources.list.d/rox-apt-repo.list

sudo apt update
sudo apt install <paquete>
```
EOF

cat > .gitignore <<'EOF'
*.deb
*.asc
!public.asc
build/
pkgroot/
EOF

# Placeholder de workflow de ejemplo (SwayFX) — editar antes de usar
cat > .github/workflows/build-swayfx.yml <<'EOF'
name: Build SwayFX .deb
on:
  workflow_dispatch:
  push:
    tags:
      - 'swayfx-v*'

jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: debian:trixie
    steps:
      - name: Clonar upstream
        run: |
          git clone --depth 1 https://github.com/WillPower3309/swayfx.git src

      - name: Instalar dependencias de build
        run: |
          apt-get update
          apt-get install -y --no-install-recommends \
            build-essential meson ninja-build git pkg-config \
            libwayland-dev wayland-protocols libxkbcommon-dev \
            libpixman-1-dev libdrm-dev libgbm-dev libinput-dev \
            libudev-dev libseat-dev libxcb-*-dev libpam0g-dev \
            libcairo2-dev libpango1.0-dev libgdk-pixbuf-2.0-dev \
            scdoc libsystemd-dev libegl1-mesa-dev libgles2-mesa-dev \
            hwdata dpkg-dev

      - name: Compilar
        working-directory: src
        run: |
          meson setup build --buildtype=release --prefix=/usr
          ninja -C build

      - name: Empaquetar .deb
        working-directory: src
        run: |
          VERSION=$(git describe --tags --always | sed 's/^v//')
          mkdir -p pkgroot/DEBIAN
          DESTDIR=$PWD/pkgroot ninja -C build install
          DEPS=$(dpkg-shlibdeps --ignore-missing-info -O \
            $(find pkgroot/usr/bin pkgroot/usr/lib -type f -executable 2>/dev/null) \
            2>/dev/null | sed 's/^shlibs:Depends=//' || echo "")
          cat > pkgroot/DEBIAN/control <<CTRL
          Package: swayfx
          Version: ${VERSION}
          Section: x11
          Priority: optional
          Architecture: amd64
          Depends: ${DEPS}
          Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
          Description: SwayFX - Sway con efectos visuales
           Fork de Sway con blur, sombras y esquinas redondeadas.
          CTRL
          dpkg-deb --build --root-owner-group pkgroot "swayfx_${VERSION}_amd64.deb"
          mv "swayfx_${VERSION}_amd64.deb" ..

      - uses: actions/upload-artifact@v4
        with:
          name: swayfx-deb
          path: swayfx_*_amd64.deb

  publish:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: gh-pages

      - uses: actions/download-artifact@v4
        with:
          name: swayfx-deb
          path: incoming

      - name: Importar GPG key
        run: echo "${{ secrets.GPG_PRIVATE_KEY }}" | gpg --batch --import

      - name: Agregar al pool y regenerar índices
        run: |
          sudo apt-get install -y dpkg-dev
          mkdir -p pool/main dists/trixie/main/binary-amd64
          cp incoming/*.deb pool/main/
          dpkg-scanpackages --arch amd64 pool/ > dists/trixie/main/binary-amd64/Packages
          gzip -9fk dists/trixie/main/binary-amd64/Packages

      - name: Generar y firmar Release
        run: |
          cd dists/trixie
          cat > Release <<REL
          Origin: rox-apt-repo
          Label: Rox Personal Repo
          Suite: trixie
          Codename: trixie
          Architectures: amd64
          Components: main
          Date: $(date -Ru)
          REL
          apt-ftparchive release . >> Release
          gpg --default-key "${{ secrets.GPG_KEY_ID }}" -abs -o Release.gpg Release
          gpg --default-key "${{ secrets.GPG_KEY_ID }}" --clearsign -o InRelease Release

      - name: Commit y push a gh-pages
        run: |
          git config user.name "github-actions"
          git config user.email "actions@github.com"
          git add pool dists
          git commit -m "Actualizar swayfx" || echo "Sin cambios"
          git push
EOF

echo "==> Inicializando git y rama gh-pages"
git init -q
git add .
git commit -q -m "Estructura inicial del repo APT"
git branch -M main

# Rama gh-pages vacía con la estructura del repo APT + public.asc placeholder
git checkout --orphan gh-pages -q
git rm -rf . >/dev/null 2>&1 || true
mkdir -p pool/main dists/trixie/main/binary-amd64
touch pool/main/.gitkeep
cat > public.asc <<'EOF'
# Reemplazá este archivo con tu clave pública real:
# gpg --armor --export TU_FINGERPRINT > public.asc
EOF
git add .
git commit -q -m "Inicializar gh-pages"
git checkout main -q

cd ..
echo ""
echo "==> Listo. Estructura creada en ./${REPO_NAME}"
echo ""
echo "Próximos pasos:"
echo "  1. cd ${REPO_NAME}"
echo "  2. Reemplazar public.asc en la rama gh-pages con tu clave real:"
echo "       git checkout gh-pages"
echo "       gpg --armor --export F852A3B9CBF59B5356307F0A1A087D9361D52D4E > public.asc"
echo "       git add public.asc && git commit -m 'Agregar clave publica' && git checkout main"
echo "  3. Crear el repo vacio en GitHub (sin README) y agregarlo como remote:"
echo "       git remote add origin git@github.com:TU_USUARIO/${REPO_NAME}.git"
echo "       git push -u origin main"
echo "       git push -u origin gh-pages"
echo "  4. En GitHub: Settings > Secrets > Actions, agregar:"
echo "       GPG_PRIVATE_KEY = contenido de private.asc"
echo "       GPG_KEY_ID      = F852A3B9CBF59B5356307F0A1A087D9361D52D4E"
echo "  5. En GitHub: Settings > Pages, publicar desde la rama gh-pages"
