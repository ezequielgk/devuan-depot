# devuan-depot

Personal APT repository for Devuan 6 (Debian 13-based). Built by GitHub Actions from source.

**Famous Packages:** Niri, SwayFX, Gamescope, Foot, wlroots, xwayland-satellite

[![Website](https://img.shields.io/badge/Website-Live-brightgreen)](https://ezequielgk.github.io/devuan-depot/)

## Install

```bash
curl -fsSL https://ezequielgk.github.io/devuan-depot/public.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/devuan-depot.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/devuan-depot.gpg] https://ezequielgk.github.io/devuan-depot trixie main" \
  | sudo tee /etc/apt/sources.list.d/devuan-depot.list

sudo apt update
sudo apt install <package>
```
