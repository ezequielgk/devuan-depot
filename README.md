# devuan-depot

[![Check Updates](https://github.com/ezequielgk/devuan-depot/actions/workflows/check-updates.yml/badge.svg)](https://github.com/ezequielgk/devuan-depot/actions/workflows/check-updates.yml)
[![Deploy Pages](https://github.com/ezequielgk/devuan-depot/actions/workflows/deploy-pages.yml/badge.svg)](https://github.com/ezequielgk/devuan-depot/actions/workflows/deploy-pages.yml)
[![Build Niri](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-niri.yml/badge.svg)](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-niri.yml)
[![Build SwayFX](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-swayfx.yml/badge.svg)](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-swayfx.yml)
[![Build Foot](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-foot.yml/badge.svg)](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-foot.yml)
[![Build wlroots](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-wlroots.yml/badge.svg)](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-wlroots.yml)
[![Build pcmanfm-qt](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-pcmanfm-qt.yml/badge.svg)](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-pcmanfm-qt.yml)
[![Build xwayland-satellite](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-xwayland-satellite.yml/badge.svg)](https://github.com/ezequielgk/devuan-depot/actions/workflows/build-xwayland-satellite.yml)

**Website:** [https://ezequielgk.github.io/devuan-depot/](https://ezequielgk.github.io/devuan-depot/)

Personal APT repository. Workflows in `.github/workflows/` build projects and publish `.deb` packages ready to install via GitHub Pages.

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
