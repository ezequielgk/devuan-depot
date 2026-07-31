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
# Custom Kernel — Cristal (trixie)

Este repositorio compila automáticamente tu kernel Devuan "cristal" a través de GitHub Actions, utilizando como base el kernel genérico oficial de Debian/Devuan, pero aplicándole configuraciones de optimización en la nube de forma automática.

## ¿Qué se le recortó al kernel genérico?

Para lograr una compilación más rápida, menos peso y estar optimizado para tu hardware, se extrae el `.config` original de Debian y se modifican las siguientes opciones:

### 1. Placas de Video que no usás (Completamente eliminadas):
- `NOUVEAU` (Drivers de Nvidia).
- `DRM_I915` (Drivers de Intel integradas antiguas).
- `DRM_RADEON` (Drivers de placas AMD muy viejas pre-GCN).
*(El driver moderno `amdgpu` que usan las gráficas actuales se mantiene intacto)*.

### 2. Sistemas de Archivos de Red (Completamente eliminados):
- Se eliminan por completo `NFS` (cliente y servidor) y `CIFS` (carpetas compartidas de Windows/Samba).

### 3. Opciones de Desarrollo (Completamente eliminadas):
- `DEBUG_INFO` y los símbolos BTF/DWARF. Esto reduce cientos de megabytes de peso extra innecesario.

### 4. Sistemas de Archivos (Convertidos en Módulos `[M]`):
- Sistemas como `BTRFS`, `XFS`, `JFS`, `NTFS` y `EXFAT` se compilan como módulos. **No consumen memoria RAM** hasta que enchufes un disco con ese formato.

---

## 1. Instalación (Solo para Devuan/Debian)

Como esto genera archivos `.deb`, la instalación en tu Devuan es idéntica a cualquier paquete oficial. Tenés dos opciones:

### Opción A: A través de tu propio repositorio APT (Recomendado)

El workflow sube automáticamente la última compilación a la rama `gh-pages` como un repositorio APT válido.
Simplemente seguí las instrucciones de instalación de la página del repositorio para agregar el origen, y luego:

```bash
sudo apt update
sudo apt install linux-image-*-cristal linux-headers-*-cristal
```

### Opción B: Descarga Manual

1. Andá a la pestaña **Releases** en este repositorio de GitHub.
2. Descargá los `.deb` generados en la última versión.
3. Instalalos con:
   ```bash
   sudo dpkg -i linux-image-*-cristal*.deb linux-headers-*-cristal*.deb
   ```

## 2. Configurar GRUB (Recomendado)

Si instalás un kernel manual, Devuan lo agregará al GRUB automáticamente, pero puede que no lo deje como predeterminado si tu kernel actual (el `deb13` oficial) tiene un número de versión superior.

Bootearlo desde el menú de grub sin ponerlo por defecto hasta confirmar que
el bluetooth, la máquina virtual y el joystick sigan funcionando perfectamente.

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
make -j$(nproc) bindeb-pkg LOCALVERSION=-custom
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
