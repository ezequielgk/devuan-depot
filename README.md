# devuan-depot

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
