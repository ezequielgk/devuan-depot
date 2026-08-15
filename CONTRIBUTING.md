# Contributing to devuan-depot

devuan-depot is a personal APT repository served via GitHub Pages at
<https://ezequielgk.github.io/devuan-depot>. It ships pre-built `.deb`
packages for Devuan 6 / Debian 13 (trixie).

## Reporting issues

Open an issue on GitHub and include:

- The package name and what you expected vs. what happened
- Output of `apt-cache policy <package>`
- Output of `apt-cache depends <package> | head -20`
- The full `apt-get` command and its output

## Packages

| Package | Source | Notes |
|---|---|---|
| `mangowc` | <https://github.com/mangowm/mango> | Wayland compositor (dwm-style) |
| `swayfx` | <https://github.com/WillPower3309/swayfx> | Sway fork with eye candy |
| `niri` | <https://github.com/YaLTeR/niri> | Scrollable-tiling Wayland compositor |
| `wlroots0.19`, `wlroots0.20` | <https://gitlab.freedesktop.org/wlroots/wlroots> | Wayland compositor library |
| `scenefx0.4`, `scenefx0.5` | <https://github.com/wlrfx/scenefx> | Drop-in `wlr_scene` replacement |
| `dwl` | <https://github.com/djpohly/dwl> | dwm for Wayland |
| `foot` | <https://codeberg.org/dnkl/foot> | Wayland terminal |
| `xwayland-satellite` | <https://github.com/Supreeeme/xwayland-satellite> | Rootless Xwayland for Wayland compositors |
| Backports | Debian sid (`libdrm`, `libwayland`, `libxkbcommon`, `pixman`, …) | Rebuilt for trixie |

## Versioning scheme

All packages built from source carry a `~devuandepot` suffix:

- Tag-based: `<tag>.<YYYYMMDD>.<run>~devuandepot` (e.g. `1.27.0.20260728.7~devuandepot`)
- Git snapshot: `0.YYYYMMDD+git<short>.<run>~devuandepot` (e.g. `0.20260728+git9ce833b.5~devuandepot`)
- Library (matrix): `<branch>~git<short>.YYYYMMDD.<run>~devuandepot`

The date as a leading component makes every re-run strictly higher than
the previous one, so `apt upgrade` always picks up the new build.

Debian sid backports keep the upstream version unchanged (no `~devuandepot`).

## Adding a new package

1. Copy the closest workflow under `.github/workflows/`:
   - `build-foot.yml` for a C/meson project
   - `build-wlroots.yml` for a library that needs `DEBIAN/shlibs`
2. In the `build` job: fetch the source, build it, stage `pkgroot/`, call
   the `dpkg-shlibdeps-deps` composite action to resolve `Depends:`.
3. In the `publish` job: use `find incoming -type f -name '*.deb' -exec
   cp -v {} pool/main/ \;` (do not use `cp incoming/*.deb` — see
   [BUILDING.md](BUILDING.md) for why), then `dpkg-scanpackages
   --multiversion pool/`, sign `Release`/`InRelease`, commit and push.
4. Trigger the workflow manually from the Actions tab.

## Repository layout

- `main` branch — workflows + the composite action
- `gh-pages` branch — the live APT repo (`pool/main/*.deb`, `dists/`)
- `.github/workflows/` — one workflow per package + `cleanup-pool.yml`
- `.github/actions/dpkg-shlibdeps-deps/` — composite action for shlib deps

See [BUILDING.md](BUILDING.md) for the full operational details.