#!/usr/bin/env bash
set -e

# These should be set by the matrix env via build-package-core.yml
if [ -z "$BRANCH" ] || [ -z "$PKG_NAME" ]; then
  echo "ERROR: BRANCH and PKG_NAME environment variables must be set"
  exit 1
fi

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Cloning wlroots branch $BRANCH..."
git clone --branch "$BRANCH" --depth 1 https://gitlab.freedesktop.org/wlroots/wlroots.git src
cd src
WLROOTS_SHORT=$(git rev-parse --short HEAD)
WLROOTS_VERSION="${BRANCH}~git${WLROOTS_SHORT}.$(date -u +%Y%m%d).${RUN_NUMBER}~devuandepot"
echo "WLROOTS_VERSION=${WLROOTS_VERSION}"

echo "Patching meson.build for versioned SONAME..."
python3 - <<'PYEOF'
import re, sys

with open('meson.build') as f:
    lines = f.readlines()

start = None
for i, line in enumerate(lines):
    if re.search(r'=\s*library\(', line):
        start = i
        break
if start is None:
    sys.exit("ERROR: library() call not found in meson.build")

end = None
for i in range(start, len(lines)):
    if lines[i].strip() == ')':
        end = i
        break
if end is None:
    sys.exit("ERROR: end of library() block not found")

if any('soversion' in l for l in lines[start:end]):
    print("soversion already set upstream; no patch needed")
    sys.exit(0)

insert_at = None
for i in range(start + 1, end):
    if 'install:' in lines[i]:
        insert_at = i
        break
if insert_at is None:
    sys.exit("ERROR: no install: kwarg found in library() block")

lines[insert_at:insert_at] = [
    "\tversion: meson.project_version(),\n",
    "\tsoversion: '0',\n",
]
with open('meson.build', 'w') as f:
    f.writelines(lines)
print("Patched: added version+soversion to library()")
PYEOF
sed -n "/= library(/,/^)/p" meson.build

echo "Compiling wlroots..."
meson setup build --buildtype=release --sysconfdir=/etc --strip -Db_lto=true -Db_ndebug=true -Db_pie=true --prefix=/usr
ninja -C build

echo "Packaging .deb..."
mkdir -p pkgroot/DEBIAN
DESTDIR=$PWD/pkgroot ninja -C build install

find pkgroot/usr/lib -name "lib*.so.*" -type f | grep -q . || {
  echo "ERROR: no versioned shared library was installed"
  exit 1
}

: > pkgroot/DEBIAN/shlibs
find pkgroot/usr/lib -name "lib*.so.*" -type f | while read -r so; do
  soname=$(objdump -p "$so" | awk '/SONAME/ {print $2}')
  libname=${soname%.so.*}
  sover=${soname##*.so.}
  if [ -z "$soname" ] || [ "$libname" = "$soname" ] || [ "$sover" = "$soname" ]; then
    echo "ERROR: unexpected SONAME '$soname' on $so"
    exit 1
  fi
  echo "${libname} ${sover} ${PKG_NAME} (>= ${WLROOTS_VERSION})" >> pkgroot/DEBIAN/shlibs
done
echo "=== Generated shlibs ==="
cat pkgroot/DEBIAN/shlibs

mkdir -p debian
cat > debian/control <<CTRLSTUB
Source: ${PKG_NAME}
Section: libs
Priority: optional
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>

Package: ${PKG_NAME}
Architecture: amd64
Description: wlroots
CTRLSTUB

set -u
SO_TARGETS=$(find pkgroot/usr/lib -name "*.so*" -type f)
if [ -z "$SO_TARGETS" ]; then
  echo "ERROR: no versioned shared libraries found to scan"
  exit 1
fi
if ! RAW_DEPS=$(dpkg-shlibdeps -O $SO_TARGETS); then
  echo "ERROR: dpkg-shlibdeps failed"
  exit 1
fi
DEPS=$(printf '%s\n' "$RAW_DEPS" | sed 's/^shlibs:Depends=//')
echo "=== Resolved Depends: ${DEPS} ==="
if [ -z "$DEPS" ]; then
  echo "ERROR: dpkg-shlibdeps resolved an EMPTY Depends for ${PKG_NAME}"
  exit 1
fi
set +u

cat > pkgroot/DEBIAN/control <<CTRL
Package: ${PKG_NAME}
Version: ${WLROOTS_VERSION}
Section: libs
Priority: optional
Architecture: amd64
Depends: ${DEPS}
Maintainer: Zeke Ezequielgk <ezequieldtz@tuta.io>
Description: wlroots (${BRANCH}) modular Wayland compositor library
CTRL

cat > pkgroot/DEBIAN/postinst <<'EOF'
#!/bin/sh
set -e
ldconfig
exit 0
EOF

cat > pkgroot/DEBIAN/postrm <<'EOF'
#!/bin/sh
set -e
ldconfig
exit 0
EOF
chmod 755 pkgroot/DEBIAN/postinst pkgroot/DEBIAN/postrm

dpkg-deb --build --root-owner-group pkgroot "${PKG_NAME}_${WLROOTS_VERSION}_amd64.deb"

# Move the output deb to the workspace root for the workflow to pick up
mv "${PKG_NAME}_${WLROOTS_VERSION}_amd64.deb" ..
echo "Build finished successfully."
