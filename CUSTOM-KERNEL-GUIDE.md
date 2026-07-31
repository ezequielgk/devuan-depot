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

### 2. Hardware you don't use (Completely removed)
- `MEDIA_SUPPORT` (Removes TV tuners, webcams, and DVB).
- `WLAN`, `MAC80211`, `CFG80211` (Removes all Wi-Fi drivers since you only use Ethernet).
- Legacy hardware like Floppy disks (`BLK_DEV_FD`), Parallel ports (`PARPORT`), IDE hard drives (`ATA_SFF`), and PCMCIA cards.
- Optical drives (`CDROM`, `BLK_DEV_SR`).
- Prehistoric Audio (`SND_ISA`, `SND_FIREWIRE`, `SND_PCMCIA`), leaving only modern HDA/USB audio.
- Obsolete game controllers (`JOYSTICK_IFORCE`, `JOYSTICK_PSXPAD`), leaving generic USB gamepad support intact.
- Rare network protocols like `ATM`, `APPLETALK`, `AX25`, `ISDN`, `HAMRADIO` (amateur radio), and `IRDA` (infrared).
*(Your Wacom tablet, touchscreen support, Bluetooth, KVM, and modern gamepads were kept fully functional).*

### 3. Virtualization & Unused Filesystems (Completely removed)
- `HYPERV` (Guest integration). Since Devuan is installed on bare-metal hardware and not inside a Windows VM, all Hyper-V integration is removed. *(KVM/QEMU/VirtIO support is kept in case you ever want to run this kernel in a VM for testing before flashing).*
- `NFS` (client and server) and `CIFS` (Windows/Samba shares) are entirely removed.
- Archaic filesystems like `MINIX_FS`, `UFS`, and old Apple filesystems (`HFS_FS`, `HFSPLUS_FS`).

### 4. Heavy Filesystems (Converted to Modules `[M]`)
- Heavy filesystems like `BTRFS`, `XFS`, `JFS`, `NTFS` and `EXFAT` are compiled as loadable modules. **They consume zero RAM** until you actually plug in a USB drive with that specific format.

### 5. Paranoia Level Trims (Extreme Edge Cases)
At this stage, the actual disk/memory savings are minimal, but since your hardware is 100% modern AMD, we safely eradicated the following museum pieces:
- **Prehistoric Buses:** `AGP` (brown slot from 2004), `EISA` & `MCA` (IBM PS/2 era).
- **Ancient Mice:** Serial port mice (`MOUSE_SERIAL`) and old Apple touchpads.
- **Fossil Networks:** Token Ring, FDDI, WiMAX, and legacy 10/100 vendors (`3COM`, `SMC`, `SIS`). *(Your modern Realtek `r8169` is completely safe).*
- **Museum Graphics:** Drivers for 3dfx Voodoo, Riva TNT2, and Matrox (`FB_3DFX`, `FB_RIVA`, etc).
- **Server Virtualization:** The `XEN` hypervisor support (used primarily in big servers/AWS).
- **Foreign Sensors:** Removed temperature monitoring code for Intel (`CORETEMP`) and VIA processors. *(Your AMD `K10TEMP` sensor is fully intact).*

### 6. Atomic & Black Hole Level Trims (The Absolute Limit)
To squeeze out the last remaining bytes of unused code without breaking your specific setup, we purged the following sub-systems:
- **Alien Laptops & Brands:** All drivers for Chromebooks (`CHROME_PLATFORMS`), Microsoft Surface, and Apple MacBooks.
- **Non-Wacom Tablets:** Drivers for Huion, XP-Pen, Ugee, and Genius tablets (keeping only Wacom).
- **Enterprise & Datacenter:** InfiniBand, Server Watchdogs (`WATCHDOG`), Non-AMD Crypto Accelerators (Intel QAT, Cavium), and LivePatching/Kexec.
- **Exotic Partitions & File Systems:** Amiga, Mac, Sun, and BSD partition tables. Dead network filesystems like Ceph, AFS, Plan 9, and Coda.
- **Dead Connectivity & Ports:** FireWire, Dial-up modems (`TELEPHONY`), CAN Bus (used in cars/factories), NFC readers, and old `GAMEPORT` MIDI connectors.
- **Android & Mobile:** Android IPC/Ashmem, and Mobile Sensors (`IIO` like gyroscopes/accelerometers).
- **Miscellaneous Junk:** Intel Microcode (`MICROCODE_INTEL`), Braille displays (`SPEAKUP`), Staging (experimental drivers), and the motherboard beep speaker (`INPUT_PCSPKR`).

*(Safety Exceptions: We kept `USB_SERIAL` for your Arduino/ESP32, `DRM_QXL` for SPICE VM guests, and USB 1.1/2.0 as modules just in case your motherboard needs them).*

### 7. Development & Debug Options (Completely removed)
- `DEBUG_INFO` and BTF/DWARF symbols are disabled. This drastically reduces compilation time and memory usage, and shaves hundreds of megabytes off the final `.deb` size.

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
