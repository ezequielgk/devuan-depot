# devuan-depot

![Devuan Crystal](https://img.shields.io/badge/Devuan-Crystal-315A72?logo=linux)
![Debian 13](https://img.shields.io/badge/Debian-13-A81D33?logo=debian)
[![Website](https://img.shields.io/badge/Website-Live-brightgreen)](https://ezequielgk.github.io/devuan-depot/)

### Infrastructure & CI/CD
[![Check Updates](https://github.com/ezequielgk/devuan-depot/actions/workflows/check-updates.yml/badge.svg)](https://github.com/ezequielgk/devuan-depot/actions/workflows/check-updates.yml)
[![Deploy Pages](https://github.com/ezequielgk/devuan-depot/actions/workflows/deploy-pages.yml/badge.svg)](https://github.com/ezequielgk/devuan-depot/actions/workflows/deploy-pages.yml)

### Package Build Status
[![Build Niri](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-niri.yml/badge.svg)](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-niri.yml)
[![Build SwayFX](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-swayfx.yml/badge.svg)](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-swayfx.yml)
[![Build Foot](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-foot.yml/badge.svg)](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-foot.yml)
[![Build wlroots](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-wlroots.yml/badge.svg)](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-wlroots.yml)
[![Build pcmanfm-qt](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-pcmanfm-qt.yml/badge.svg)](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-pcmanfm-qt.yml)
[![Build xwayland-satellite](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-xwayland-satellite.yml/badge.svg)](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-xwayland-satellite.yml)

Personal APT repository. Workflows in `.github/workflows/` build projects and publish `.deb` packages ready to install via GitHub Pages.

> [!WARNING]
> **Do not install the `linux-image-*-crystal` kernel from this repository without reading the guide first!**
> This kernel is heavily trimmed down for a very specific hardware configuration. It removes most Wi-Fi drivers, NVIDIA/Intel GPUs, and legacy hardware. Installing it on a different machine will likely result in missing hardware support or an unbootable system.
> Please read [CUSTOM-KERNEL-GUIDE.md](./CUSTOM-KERNEL-GUIDE.md) to understand exactly what was removed before using it.

## Installation (on Devuan 6 / Debian 13)

### 1. Import repo public key
```bash
curl -fsSL https://ezequielgk.github.io/devuan-depot/public.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/devuan-depot.gpg
```

### 2. Add the repo
```bash
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/devuan-depot.gpg] https://ezequielgk.github.io/devuan-depot trixie main" \
  | sudo tee /etc/apt/sources.list.d/devuan-depot.list
```

### 3. Install
```bash
sudo apt update
sudo apt install <package>
```
