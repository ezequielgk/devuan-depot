# kernel-build-action — Excalibur (Devuan)

Compile your custom Devuan kernel "excalibur" via GitHub Actions, from
a `.config` you create yourself on your machine (using `localmodconfig` +
`menuconfig`), and let it keep itself updated with the versions published
by Debian trixie.

## How it decides when to compile

The workflow has three triggers:

1. **`push`** to `kernel-config/.config` (you changed the config manually) →
   always compiles, using the latest version available in trixie.
2. **`workflow_dispatch`** (you run it manually) → always compiles.
   If you provide `kernel_source_version`, it uses that; if left empty, it uses the
   latest available.
3. **`schedule`** (daily cron, 06:00 UTC) → this is where the automatic
   check comes in: a `check` job runs first, checks the latest version of `linux`
   in the trixie repo, compares it against `kernel-config/last-built-version.txt`
   (which the workflow itself updates after every successful build), and
   **only triggers the build if it changed**. If there is no new version, the
   compilation job is skipped entirely — it doesn't waste Actions minutes
   compiling the same thing every day.

## Why it runs inside a `debian:trixie` container

Your current kernel is literally the Debian 13 (trixie) package that
Devuan repackages without touching it — Devuan only changes the init system.
That's why `apt-get source linux` inside that container brings you the
correct package, with the **postinst hooks** that automatically regenerate
initramfs and grub when the `.deb` is installed.

## Initial Setup (only once, on your real Devuan machine)

Follow `GUIA-KERNEL-CUSTOM.md` in this repo to generate the `.config`:
copy the config of your current kernel, run `localmodconfig` (with
`yes n |`, since bluetooth/kvm/gamepad stay because you use them), and
adjust in `menuconfig` the filesystems as modules, exclude the GPUs you
don't have, and exclude network filesystems.

```bash
cp .config /path/to/repo/kernel-config/.config
git add kernel-config/.config
git commit -m "config: baseline excalibur"
git push
```

This triggers the first build automatically.

## Manual Usage

Actions → "Build Custom Kernel - Excalibur (Devuan/Debian trixie)" → "Run
workflow". Optional inputs:

- `kernel_source_version`: exact version of the `linux` source package in
  trixie (e.g. `6.12.48-1`). Empty = latest available at that moment.
- `localversion`: name suffix (default `-excalibur`, you will almost never
  need to change it).

## What you get back

- **Artifact** (30 days): `linux-image-*.deb`, `linux-headers-*.deb`,
  `SHA256SUMS.txt`, named `excalibur-<version>`.
- It always creates a GitHub **Release** with those same files
  (`excalibur-<version>-<run_number>`), with installation instructions
  in the body.

## Install on your Devuan

```bash
sudo dpkg -i linux-image-*-excalibur*.deb linux-headers-*-excalibur*.deb
```

Since the package brings the Debian/Devuan hooks, the `postinst` script
should regenerate initramfs and update grub by itself. If for some reason it doesn't:

```bash
sudo update-initramfs -c -k <version>-excalibur
sudo update-grub
```

Boot it from the grub menu without setting it as default until you confirm that
bluetooth, the VM, and the gamepad still work fine.

## Updating the `.config` in the future

There's no need to repeat `menuconfig` from scratch. On your machine:

```bash
apt-get source linux   # downloads the new trixie version
cd linux-*/
cp /path/to/repo/kernel-config/.config .
make oldconfig          # only prompts you for the new options
cp .config /path/to/repo/kernel-config/.config
git add kernel-config/.config && git commit -m "config: bump" && git push
```

## Notes

- `kernel-config/last-built-version.txt` is maintained by the workflow alone —
  do not edit it manually, it's what the daily check uses to know if it has
  already compiled that version or not.
- The `ccache` cache speeds up recompilations of the same `.config`, but
  the first build of a new version will take just as long (~40-60 min on
  standard GitHub runners).
- The job needs write permission to the repo (`permissions: contents: write`
  in the workflow) to be able to commit the version file after each
  successful build.


# Custom Kernel — trimming unused hardware/subsystems

Run this on your real machine (Devuan), not in a container. You'll need
~30-60 min for compilation at the end, depending on your CPU.

## 0. Dependencies

```bash
sudo apt install build-essential libncurses-dev bison flex libssl-dev \
    libelf-dev fakeroot dpkg-dev debhelper bc rsync kmod
```

## 1. Get the source (you will use the same one as your running kernel)

```bash
mkdir -p ~/kernel-build && cd ~/kernel-build
apt source linux-image-$(uname -r)
cd linux-*/
```

## 2. Base config + localmodconfig (already solved by your responses)

```bash
cp /boot/config-$(uname -r) .config
make olddefconfig
make localmodconfig
```

It will ask you about unloaded modules. Based on what we discussed, the
answer is simple: **say no (N) to everything it asks**, because
we already know that bluetooth, kvm, gamepad, and all your real hardware are
already loaded and therefore are already in the .config. What it asks you is
precisely what you do not use.

Shortcut to avoid pressing N manually on every question:

```bash
yes n | make localmodconfig
```

## 3. menuconfig — here goes the subsystem trimming

```bash
make menuconfig
```

Navigation: arrow keys to move, Enter to enter a submenu, `Space`
to cycle Y/M/N (Y=built-in, M=module, N=exclude), `/` to search by
name, Esc twice to exit a submenu.

### GPUs you don't have (leave only AMD)

`Device Drivers` → `Graphics support` → `Direct Rendering Manager`:
- `AMD GPU` → leave as `M` or `Y` (yours)
- `Nouveau (NVIDIA) cards` → set to `N`
- `Intel 8xx/9xx/G3x/G4x/G45/HD Graphics` → set to `N`
- `ATI Radeon` (the old `radeon` driver, not `amdgpu`) → set to `N` if you
  don't have pre-GCN Radeon hardware

### Filesystems — adjusted for varied USB drive usage

Since you format USB drives often and don't always know what format you'll
encounter, the best move is to use the `[M]` (module) state instead of `[ ]`
(exclude) for filesystems "just in case". A module doesn't take up memory
until you plug in a drive of that type — it's the difference between "not
installed" and "installed but sleeping until needed".

Leave as `[*]` (built-in, always present — these are the ones you mount all
the time):
- `The Extended 4 (ext4) filesystem`
- `DOS/FAT/EXFAT/NT Filesystems` → `MSDOS fs support`, `VFAT`

Leave as `[M]` (module, loads only if you plug in such a drive):
- `Btrfs filesystem support`
- `XFS filesystem support`
- `JFS filesystem support`
- `Reiserfs support`
- `DOS/FAT/EXFAT/NT Filesystems` → `NTFS Filesystem` and `exFAT filesystem
  support` (even if you currently use `ntfs-3g`/FUSE for your `/mnt/Personal`,
  having the native driver as a module costs nothing at rest)

Exclude completely, `[ ]` (confirmed that you don't need it — nothing of yours is over
the network):
- `Network File Systems` → `NFS client support`, `NFS server support`,
  `CIFS support` (the whole submenu)

### Architectures — doesn't apply at the menuconfig level

This isn't actually selected here: the `.config` you copied from
`/boot/config-$(uname -r)` is already specific to `x86_64`, because it's the
config of the Debian kernel you are running now, compiled for your arch. There
is no "ARM support" mixed into an x86_64 kernel to remove — this point is already
resolved out of the box.

### Debug options — turn off everything you don't need to diagnose kernel bugs

`Kernel hacking` → `Kernel debugging`:
- `Compile the kernel with debug info` → `N` (unless you are debugging
  the kernel itself with gdb, it doesn't apply to normal use)
- `Kernel debugging` → leave most submenus there as `N`, unless you
  know you need a specific one

Save and exit (`Save` at the bottom of the menu, or Esc → "Yes" on exit).

## 4. Compile

```bash
make -j$(nproc) deb-pkg LOCALVERSION=-custom
```

## 5. Install

```bash
cd ..
sudo dpkg -i linux-image-*-custom_*.deb linux-headers-*-custom_*.deb
```

## 6. Reboot and choose the new kernel in the GRUB menu

Don't set it as default yet. Once inside:

```bash
uname -r                    # confirm it is the -custom
lsmod | wc -l               # compare against the previous 143
dmesg | grep -iE "error|fail"
```

Test bluetooth, a game with the gamepad, and a small VM to confirm that
the three fronts you mentioned still work. If everything is fine for a couple of
days, then:

```bash
sudo update-grub    # make sure it stays as default, or edit /etc/default/grub
```

## Save the .config for the future

```bash
cp .config ~/kernel-build/config-custom-$(uname -r)-backup
```

This is the file you later upload to `kernel-config/.config` in the GitHub
Actions workflow repo we set up, to automate future builds
without repeating the whole process manually.
