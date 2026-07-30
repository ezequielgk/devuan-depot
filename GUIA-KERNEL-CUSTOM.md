# kernel-build-action (Devuan)

Compile your custom Devuan kernel via GitHub Actions, from a
`.config` you create yourself on your machine (using `localmodconfig` +
`menuconfig`).

## Why the workflow runs inside a `debian:trixie` container

Your current kernel (`6.12.95+deb13-amd64`) is literally the Debian 13 (trixie)
package that Devuan repackages without touching the kernel itself — Devuan
only changes the init system (systemd → runit/sysvinit), not the kernel. Therefore,
the correct source package to compile is the `linux` package from trixie, containing
all the patches and **postinst hooks** (the ones that regenerate initramfs and
update grub automatically when you install the `.deb`).

If you instead download the vanilla tarball from kernel.org and build the `.deb` by
hand, you lose those hooks — it works, but you have to run `update-initramfs` and
`update-grub` manually every time. That's why the workflow uses
`container: image: debian:trixie` in the job: this way, `apt-get source linux`
gets you exactly the same package used by your Devuan installation.

## Initial Setup (only once, on your real Devuan machine)

Follow the guide in this repo (below) to generate the
`.config`: you copy the config of your current kernel, run `localmodconfig`
(with `yes n |` because bluetooth/kvm/gamepad are already loaded), and adjust
in `menuconfig` the filesystems as modules, remove the GPUs you don't have,
and remove network filesystems.

```bash
cp .config /path/to/repo/kernel-config/.config
git add kernel-config/.config
git commit -m "config: baseline with bluetooth/kvm/gamepad + fs as modules"
git push
```

This triggers the workflow automatically (the `push` trigger watches for
changes in `kernel-config/.config`).

## Manual Usage

Actions → "Build Custom Kernel (Devuan/Debian trixie)" → "Run workflow".
Optional inputs:

- `kernel_source_version`: exact version of the `linux` source package in
  trixie (e.g. `6.12.48-1`). Empty = grabs the latest available in the
  Debian repo at that moment.
- `localversion`: suffix for the compiled kernel name (default
  `-custom`).

## What you get back

- **Artifact** (30 days): `linux-image-*.deb`, `linux-headers-*.deb`,
  `SHA256SUMS.txt`.
- If the push was to `main`, a GitHub **Release** is created with the same
  files and installation instructions in the body.

## Install on your Devuan

```bash
sudo dpkg -i linux-image-*.deb linux-headers-*.deb
```

Since the package comes with the Debian/Devuan hooks, the `postinst`
script should regenerate the initramfs and update grub by itself. If for
some reason it doesn't:

```bash
sudo update-initramfs -c -k <version>
sudo update-grub
```

Boot it from the grub menu without setting it as default until you confirm that
bluetooth, the VM, and the gamepad still work fine.

## Update to a new kernel version

There's no need to repeat `menuconfig` from scratch. On your machine:

```bash
apt-get source linux   # downloads the new trixie version
cd linux-*/
cp /path/to/repo/kernel-config/.config .
make oldconfig          # only prompts you for the new options
cp .config /path/to/repo/kernel-config/.config
git add kernel-config/.config && git commit -m "config: bump version" && git push
```

## Notes

- The `ccache` cache speeds up recompilations of the same `.config`, but
  the first build of a new version will take just as long (full kernel
  from scratch, ~40-60 min on standard GitHub runners).
- If you ever add proprietary firmware or extra patches specific to your
  hardware, they should be added as an extra step before "Compile".


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
