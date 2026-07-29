#!/usr/bin/env bash
set -e

# Este script arma un rootfs autocontenido de Steam (vía RunImage/pacman,
# igual que el AppImage original) pero se detiene en el paso de generar
# ./AppDir, en vez de convertirlo a AppImage/AppBundle. Ese ./AppDir es lo
# que después empaqueta scripts/package-deb.sh en un .deb.

export ARCH="$(uname -m)"

if [ ! -x 'runimage' ]; then
	echo '== download base RunImage'
	curl -o runimage -L "https://github.com/VHSgunzo/runimage/releases/download/continuous/runimage-$(uname -m)"
	chmod +x runimage
fi

run_install() {
	set -e

	INSTALL_PKGS=(
		steam egl-wayland vulkan-radeon lib32-vulkan-radeon
		vulkan-intel lib32-vulkan-intel vulkan-nouveau lib32-vulkan-nouveau
		lib32-libpipewire libpipewire pipewire
		lib32-libpipewire libpulse lib32-libpulse vkd3d lib32-vkd3d wget
		vulkan-mesa-layers lib32-vulkan-mesa-layers freetype2 lib32-freetype2 fuse2
		mangohud lib32-mangohud gamescope gamemode zenity-gtk3 steam-screensaver-fix
	)

	echo '== disabling blackarch to prevent timeouts'
	sed -i '/\[blackarch\]/,$d' /etc/pacman.conf

	echo '== checking for updates'
	rim-update

	echo '== install packages'
	pac --needed --noconfirm -S "${INSTALL_PKGS[@]}"

	echo '== install glibc with patches for Easy Anti-Cheat (optionally)'
	yes|pac -S glibc-eac lib32-glibc-eac

	echo '== install debloated packages for space saving (optionally)'
	EXTRA_PACKAGES="https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/refs/heads/main/useful-tools/get-debloated-pkgs.sh"
	wget --retry-connrefused --tries=30 "$EXTRA_PACKAGES" -O ./get-debloated-pkgs.sh
	chmod +x ./get-debloated-pkgs.sh
	./get-debloated-pkgs.sh --add-mesa llvm-libs gtk3-mini opus-mini libxml2-mini gdk-pixbuf2-mini librsvg-mini icu-mini

	pac -Rsn --noconfirm llvm-libs || true
	pac -Rsn --noconfirm glycin || true

	VERSION=$(pacman -Q steam | awk 'NR==1 {print $2; exit}')
	[ -n "$VERSION" ] && echo "$VERSION" > ~/version

	echo '== shrink (optionally)'
	pac -Rsndd --noconfirm wget gocryptfs jq gnupg perl
	rim-shrink --all
	pac -Rsndd --noconfirm binutils gettext

	cp /usr/share/icons/hicolor/256x256/apps/steam.png ~/
	cp /usr/share/applications/steam.desktop ~/

	ln -sf /var/host/bin/xdg-open /usr/bin/xdg-open

	# allow steam to run as root (uid 69 trick, igual que el original)
	sed -i 's|"$(id -u)" == "0"|"$(id -u)" == "69"|' /usr/lib/steam/bin_steam.sh
	sed -i 's|\[ ! -L "$DESKTOP_DIR/$STEAMPACKAGE.desktop" \]|false|' /usr/lib/steam/bin_steam.sh

	echo '== create RunImage config for app (optionally)'
	cat <<- 'EOF' > "$RUNDIR/config/Run.rcfg"
	RIM_CMPRS_LVL="${RIM_CMPRS_LVL:=22}"
	RIM_CMPRS_BSIZE="${RIM_CMPRS_BSIZE:=25}"
	RIM_HOST_XDG_OPEN="${RIM_HOST_XDG_OPEN:=1}"
	RIM_SYS_NVLIBS="${RIM_SYS_NVLIBS:=1}"
	RIM_NVIDIA_DRIVERS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/runimage_nvidia"
	RIM_SHARE_ICONS="${RIM_SHARE_ICONS:=1}"
	RIM_SHARE_FONTS="${RIM_SHARE_FONTS:=1}"
	RIM_SHARE_THEMES="${RIM_SHARE_THEMES:=1}"
	RIM_HOST_TOOLS=git,xxd,xwininfo,xdotool,wget,unzip,yad
	RIM_BIND="/usr/share/locale:/usr/share/locale,/usr/lib/locale:/usr/lib/locale${RIM_EXTRA_BIND:+,${RIM_EXTRA_BIND}}"
	RIM_COPY_RESOLVCONF=1
	RIM_WAIT_RPIDS_EXIT=1
	RIM_AUTORUN=steam-screensaver-fix-runtime
	EOF

	echo '== Build new DwarFS runimage with zstd 22 lvl and 24 block size'
	rim-build -s steam.RunImage
}
export -f run_install

RIM_OVERFS_MODE=1 RIM_NO_NVIDIA_CHECK=1 ./runimage bash -c run_install
./steam.RunImage --runtime-extract
rm -f ./steam.RunImage

mv ./RunDir ./AppDir
mv ./AppDir/Run ./AppDir/AppRun

ln -s ./steam ./AppDir/rootfs/usr/bin/steam-runtime || true
ln -s ./steam ./AppDir/rootfs/usr/bin/steam-native || true

# debloat (igual que el original)
rm -rfv ./AppDir/sharun/bin/chisel \
	./AppDir/rootfs/usr/lib*/libgo.so* \
	./AppDir/rootfs/usr/lib*/libgphobos.so* \
	./AppDir/rootfs/usr/lib*/libgfortran.so* \
	./AppDir/rootfs/usr/bin/rsvg-convert \
	./AppDir/rootfs/usr/bin/rav1e \
	./AppDir/rootfs/usr/*/*pacman* \
	./AppDir/rootfs/usr/share/gir-1.0 \
	./AppDir/rootfs/var/lib/pacman \
	./AppDir/rootfs/etc/pacman* \
	./AppDir/rootfs/usr/share/licenses \
	./AppDir/rootfs/usr/share/terminfo \
	./AppDir/rootfs/usr/share/icons/AdwaitaLegacy \
	./AppDir/rootfs/usr/lib/udev/hwdb.bin

echo "Bundle listo en ./AppDir (versión: $(cat ~/version))"
