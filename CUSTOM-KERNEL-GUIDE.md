# Custom Kernel — Crystal (Devuan/Debian trixie)

This repository automatically compiles your Devuan "crystal" custom kernel via GitHub Actions. It uses the official generic Debian/Devuan kernel as a base, but applies heavy optimizations and hardware-specific trimming in the cloud.

## How it decides when to compile

The workflow has three triggers:

1. **`push`** to `kernel-config/.config` (you changed the config manually) → always compiles, using the latest version available in trixie.
2. **`workflow_dispatch`** (you run it manually) → always compiles. If you provide `kernel_source_version`, it uses that; if left empty, it uses the latest available.
3. **`schedule`** (daily cron, 06:00 UTC) → this is where the automatic check comes in: a `check` job runs first, checks the latest version of `linux` in the trixie repo, compares it against `kernel-config/last-built-version.txt` (which the workflow itself updates after every successful build), and **only triggers the build if it changed**. If there is no new version, the compilation job is skipped entirely — it doesn't waste Actions minutes.

## What was removed from the generic kernel?

To achieve a faster build, smaller size, and optimization for your specific hardware, the original Debian `.config` was trimmed down automatically by our workflow:

### 1. GPUs you don't use (Completely removed)
- `NOUVEAU` (Nvidia open source drivers)
- `DRM_I915` (Intel integrated graphics drivers)
- `DRM_RADEON` (Old pre-GCN AMD drivers)
*(The modern `amdgpu` driver used by your graphics card is kept intact).*

### 2. Sniper Mode: Hardware you don't use (Completely removed)
- `MEDIA_SUPPORT` (Removes TV tuners, webcams, and DVB).
- `WLAN`, `MAC80211`, `CFG80211` (Removes all Wi-Fi drivers since you only use Ethernet).
- Legacy hardware like Floppy disks (`BLK_DEV_FD`), Parallel ports (`PARPORT`), IDE hard drives (`ATA_SFF`), and PCMCIA cards.
- Rare network protocols like `ATM`, `APPLETALK`, `AX25`, and `ISDN`.
*(Your Wacom tablet, touchscreen support, Bluetooth, KVM, and gamepads were kept fully functional).*

### 3. Network Filesystems (Completely removed)
- `NFS` (client and server) and `CIFS` (Windows/Samba shares) are entirely removed.

### 4. Development & Debug Options (Completely removed)
- `DEBUG_INFO` and BTF/DWARF symbols are disabled. This drastically reduces compilation time and memory usage, and shaves hundreds of megabytes off the final `.deb` size.

### 5. Filesystems (Converted to Modules `[M]`)
- Heavy filesystems like `BTRFS`, `XFS`, `JFS`, `NTFS` and `EXFAT` are compiled as loadable modules. **They consume zero RAM** until you actually plug in a USB drive with that specific format.

---

## 1. Installation (Devuan/Debian only)

Since this generates standard `.deb` packages, installation on your Devuan machine is identical to any official package.

### Option A: Via your own APT repository (Recommended)

The workflow automatically uploads the latest build to the `gh-pages` branch, serving it as a valid APT repository.
Just follow the setup instructions on the GitHub Pages site for this repo to add the source, and then run:

```bash
sudo apt update
sudo apt install linux-image-*-crystal linux-headers-*-crystal
```

### Option B: Manual Download

1. Go to the **Releases** tab in this GitHub repository.
2. Download the `.deb` files generated for the latest release.
3. Install them manually with:
   ```bash
   sudo dpkg -i linux-image-*-crystal*.deb linux-headers-*-crystal*.deb
   ```

## 2. Configuring GRUB (Recommended)

When you install a custom kernel, Devuan adds it to GRUB automatically. If your new kernel has the `-crystal` suffix, it will usually be placed at the top of the boot list and run by default.

Reboot and confirm everything works as expected:

```bash
uname -r                    # confirm it is the -crystal kernel
lsmod | wc -l               # check the number of loaded modules
dmesg | grep -iE "error|fail"
```

Test your bluetooth, your gamepad, and your virtual machines to confirm that everything is functioning perfectly.

## Updating the `.config` manually in the future (Optional)

Our automated workflow already takes care of the trimming. However, if you ever want to run `menuconfig` on your machine to further tweak the base configuration:

```bash
apt-get source linux   # downloads the latest trixie source
cd linux-*/
cp /path/to/repo/kernel-config/.config .
make oldconfig          # only prompts you for new kernel options
make menuconfig         # make your custom changes
cp .config /path/to/repo/kernel-config/.config
git add kernel-config/.config && git commit -m "config: manual update" && git push
```

## Notes

- `kernel-config/last-built-version.txt` is maintained by the workflow alone — do not edit it manually, it's what the daily check uses to know if it has already compiled that version.
- The `ccache` integration speeds up recompilations of the same `.config`, but the first build of a new Debian upstream version will take the usual time (~40-60 min on standard GitHub runners).
- The workflow needs write permission to the repository (`permissions: contents: write`) to be able to commit the version file after each successful build and push the APT repository to `gh-pages`.
