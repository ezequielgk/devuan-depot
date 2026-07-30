# kernel-build-action (Devuan)

Compila tu kernel Devuan custom vía GitHub Actions, a partir de un
`.config` que armás vos mismo en tu máquina (con `localmodconfig` +
`menuconfig`).

## Por qué el workflow corre dentro de un contenedor `debian:trixie`

Tu kernel actual (`6.12.95+deb13-amd64`) es literalmente el paquete de
Debian 13 (trixie) que Devuan repackagea sin tocar el kernel en sí — Devuan
solo cambia el init system (systemd → runit/sysvinit), no el kernel. Por
eso el paquete fuente correcto para compilar es el `linux` de trixie, con
todos los parches y **hooks de postinst** (los que regeneran initramfs y
actualizan grub automáticamente al instalar el `.deb`).

Si en cambio bajás el tarball vanilla de kernel.org y armás el `.deb` a
mano, te queda sin esos hooks — funciona, pero tenés que correr
`update-initramfs` y `update-grub` manualmente cada vez. Por eso el
workflow usa `container: image: debian:trixie` en el job: así `apt-get
source linux` te trae exactamente el mismo paquete que usa tu Devuan.

## Setup inicial (una sola vez, en tu Devuan real)

Seguí la guía `GUIA-KERNEL-CUSTOM.md` de este mismo repo para generar el
`.config`: copiás el config de tu kernel actual, corrés `localmodconfig`
(con `yes n |` porque bluetooth/kvm/gamepad ya están cargados), y ajustás
en `menuconfig` los filesystems como módulo, las GPUs que no tenés fuera,
y las network filesystems fuera.

```bash
cp .config /path/to/repo/kernel-config/.config
git add kernel-config/.config
git commit -m "config: baseline con bluetooth/kvm/gamepad + fs como módulo"
git push
```

Esto dispara el workflow automáticamente (el trigger de `push` mira
cambios en `kernel-config/.config`).

## Uso manual

Actions → "Build Custom Kernel (Devuan/Debian trixie)" → "Run workflow".
Inputs opcionales:

- `kernel_source_version`: versión exacta del paquete fuente `linux` en
  trixie (por ejemplo `6.12.48-1`). Vacío = trae la última disponible en
  el repo de Debian en ese momento.
- `localversion`: sufijo del nombre del kernel compilado (default
  `-custom`).

## Qué te devuelve

- **Artifact** (30 días): `linux-image-*.deb`, `linux-headers-*.deb`,
  `SHA256SUMS.txt`.
- Si el push fue a `main`, además un **Release** de GitHub con los mismos
  archivos e instrucciones de instalación en el body.

## Instalar en tu Devuan

```bash
sudo dpkg -i linux-image-*.deb linux-headers-*.deb
```

Como el paquete viene con los hooks de Debian/Devuan, el `postinst`
debería regenerar initramfs y actualizar grub solo. Si por algo no lo
hace:

```bash
sudo update-initramfs -c -k <version>
sudo update-grub
```

Bootealo desde el menú de grub sin ponerlo default hasta confirmar que
bluetooth, la VM, y el gamepad siguen andando bien.

## Actualizar a una versión nueva del kernel

No hace falta repetir `menuconfig` desde cero. En tu máquina:

```bash
apt-get source linux   # baja la versión nueva de trixie
cd linux-*/
cp /path/to/repo/kernel-config/.config .
make oldconfig          # te pregunta solo por las opciones nuevas
cp .config /path/to/repo/kernel-config/.config
git add kernel-config/.config && git commit -m "config: bump versión" && git push
```

## Notas

- El cache de `ccache` acelera recompilaciones del mismo `.config`, pero
  la primera build de una versión nueva tarda igual (kernel completo
  desde cero, ~40-60 min en runners estándar de GitHub).
- Si en algún momento agregás firmware propietario o parches extra
  específicos de tu hardware, se suman como paso adicional antes de
  "Compilar".


# Kernel custom — recorte de hardware/subsistemas no usados

Corré esto en tu máquina real (Devuan), no en un contenedor. Vas a necesitar
~30-60 min de compilación al final, según tu CPU.

## 0. Dependencias

```bash
sudo apt install build-essential libncurses-dev bison flex libssl-dev \
    libelf-dev fakeroot dpkg-dev debhelper bc rsync kmod
```

## 1. Conseguir el source (vas a usar el mismo del kernel que ya corrés)

```bash
mkdir -p ~/kernel-build && cd ~/kernel-build
apt source linux-image-$(uname -r)
cd linux-*/
```

## 2. Config base + localmodconfig (ya resuelto con tus respuestas)

```bash
cp /boot/config-$(uname -r) .config
make olddefconfig
make localmodconfig
```

Te va a preguntar por módulos no cargados. Con lo que ya charlamos, la
respuesta es simple: **decile que no (N) a todo lo que te pregunte**, porque
ya sabemos que bluetooth, kvm, gamepad, y todo tu hardware real ya están
cargados y por lo tanto ya están en el .config. Lo que te pregunte es
justamente lo que no usás.

Atajo para no ir tocando N a mano en cada pregunta:

```bash
yes n | make localmodconfig
```

## 3. menuconfig — acá va el recorte de subsistemas

```bash
make menuconfig
```

Navegación: flechas para moverte, Enter para entrar a un submenú, `Espacio`
para ciclar Y/M/N (Y=integrado, M=módulo, N=fuera), `/` para buscar por
nombre, Esc dos veces para salir de un submenú.

### GPUs que no tenés (dejar solo AMD)

`Device Drivers` → `Graphics support` → `Direct Rendering Manager`:
- `AMD GPU` → dejar en `M` o `Y` (la tuya)
- `Nouveau (NVIDIA) cards` → poner en `N`
- `Intel 8xx/9xx/G3x/G4x/G45/HD Graphics` → poner en `N`
- `ATI Radeon` (el driver viejo `radeon`, no `amdgpu`) → poner en `N` si no
  tenés hardware Radeon pre-GCN

### Filesystems — ajustado por el uso de discos USB variados

Como formateás discos USB seguido y no siempre sabés con qué formato vas a
encontrarte, la jugada es usar el estado `[M]` (módulo) en vez de `[ ]`
(fuera) para los filesystems "por las dudas". Un módulo no ocupa memoria
hasta que conectás un disco de ese tipo — es la diferencia entre "no está
instalado" y "está instalado pero dormido hasta que haga falta".

Dejar en `[*]` (integrado, siempre presente — son los que montás todo el
tiempo):
- `The Extended 4 (ext4) filesystem`
- `DOS/FAT/EXFAT/NT Filesystems` → `MSDOS fs support`, `VFAT`

Dejar en `[M]` (módulo, carga solo si conectás un disco así):
- `Btrfs filesystem support`
- `XFS filesystem support`
- `JFS filesystem support`
- `Reiserfs support`
- `DOS/FAT/EXFAT/NT Filesystems` → `NTFS Filesystem` y `exFAT filesystem
  support` (por más que uses `ntfs-3g`/FUSE para tu `/mnt/Personal` actual,
  tener el driver nativo como módulo no cuesta nada en reposo)

Sacar del todo, `[ ]` (confirmado que no lo necesitás — nada tuyo es por
red):
- `Network File Systems` → `NFS client support`, `NFS server support`,
  `CIFS support` (todo el submenú)

### Arquitecturas — no aplica a nivel menuconfig

Esto en realidad no se elige acá: el `.config` que copiaste de
`/boot/config-$(uname -r)` ya es específico para `x86_64`, porque es la
config del kernel de Debian que corrés ahora, compilado para tu arch. No
hay "soporte ARM" mezclado en un kernel x86_64 para sacar — este punto ya
viene resuelto de fábrica.

### Debug options — apagar todo lo que no necesitás para diagnosticar bugs del kernel en sí

`Kernel hacking` → `Kernel debugging`:
- `Compile the kernel with debug info` → `N` (a menos que estés debuggeando
  el kernel mismo con gdb, no aplica a uso normal)
- `Kernel debugging` → dejar en `N` la mayoría de submenús ahí, salvo que
  sepas que necesitás alguno específico

Guardá y salí (`Save` al fondo del menú, o Esc → "Yes" al salir).

## 4. Compilar

```bash
make -j$(nproc) deb-pkg LOCALVERSION=-custom
```

## 5. Instalar

```bash
cd ..
sudo dpkg -i linux-image-*-custom_*.deb linux-headers-*-custom_*.deb
```

## 6. Reboot y elegir el kernel nuevo en el menú de GRUB

No lo pongas default todavía. Una vez adentro:

```bash
uname -r                    # confirmar que es el -custom
lsmod | wc -l               # comparar contra los 143 de antes
dmesg | grep -iE "error|fail"
```

Probá bluetooth, un juego con el gamepad, y una VM chica para confirmar que
los tres frentes que dijiste usar siguen andando. Si todo bien un par de
días, ahí sí:

```bash
sudo update-grub    # asegurate que quede como default, o editá /etc/default/grub
```

## Guardar el .config para el futuro

```bash
cp .config ~/kernel-build/config-custom-$(uname -r)-backup
```

Este es el archivo que después subís a `kernel-config/.config` en el repo
del workflow de GitHub Actions que armamos, para automatizar builds futuros
sin repetir todo el proceso a mano.
