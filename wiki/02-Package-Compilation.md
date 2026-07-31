# Package Compilation (`build-*.yml`)

In your repository, you will notice a lot of files starting with `build-`, like `build-niri.yml` or `build-swayfx.yml`. They all share a common goal: download the newest source code of the program, compile it, turn it into a `.deb` file, and upload it to the repository.

## The Step-by-Step of a Compilation

To understand why they work and why they never fail, let's break down what happens inside the server every time you run one of these workflows. Let's take **Niri** as an example:

### 1. The Environment (Debian/Devuan Trixie)
The first thing the script does is download the official `debian:trixie` Docker image. This guarantees that the package is compiled with the exact same versions of `libc6` and `wayland` that the users installing the package will have on their PCs.

### 2. Installing Build Dependencies (Build-Depends)
Before we can compile anything, we need the tools. The script executes a massive `apt-get install` installing:
- Compilation tools: `gcc`, `clang`, `cargo` (for Rust), `meson`, `cmake`.
- Development libraries (`-dev`): `libwayland-dev`, `libgbm-dev`, etc.
**Why does it always work?** Because the list is explicitly written in the YAML, ensuring a library is never missing. Furthermore, in packages like `wlroots`, we use your *own* Devuan-Depot repository as a secondary source to force the use of *backports* (updated versions) instead of the old ones that come with Debian.

### 3. Downloading the Original Source Code (Git Clone)
Instead of relying on pre-made packages, we query the GitHub or Gitlab API of the original project (`YaLTeR/niri`) to get the tag of its latest version (e.g., `v0.1.7`). Once we know it, we do a `git clone` of that specific branch.

### 4. Compilation
Depending on the language, we execute `cargo build --release` (for Rust programs like Niri or Concord) or `meson setup build && ninja -C build` (for C programs like SwayFX or Foot). This produces the actual executable binaries.

### 5. Building the Filesystem (`pkgroot`)
A `.deb` file is nothing more than a compressed folder (literally).
We create a temporary folder called `pkgroot`, and inside we recreate the Linux filesystem directory structure:
- `pkgroot/usr/bin/`: We put the binaries there.
- `pkgroot/usr/share/wayland-sessions/`: We put the `.desktop` files so the program appears on your Login screen (Display Manager).
- `pkgroot/DEBIAN/`: This special folder is mandatory. Inside it goes a file called `control` that holds the metadata (Package name, version, maintainer, architecture).

### 6. The Magic of Automatic Dependencies (`dpkg-shlibdeps`)
This is the most critical step of the entire repository.
How does the Niri `.deb` know which libraries to require the user to have installed when they do `apt install niri`?
Instead of writing them by hand, we use a local Action of yours called `dpkg-shlibdeps-deps`. This program scans the already compiled binaries, checks what `.so` files they need to run, and auto-generates a `${DEPS}` variable (e.g., `libc6 (>= 2.34), libwayland-client0 (>= 1.20)`).
This is why Devuan-Depot packages never break dependencies!

### 7. Secure Versioning (`~devuandepot`)
To avoid conflicts with official Debian packages, we inject the `~devuandepot` suffix and the date into all your builds.
Example: `0.1.7.20260728.45~devuandepot`.
The final number (`45`) is the `github.run_number` (how many times you ran this workflow in history). By always incrementing, we guarantee that every time you press the "Run Workflow" button, `apt` interprets the new `.deb` as a mathematically higher version than the previous one, forcing the update.

### 8. Final Packaging and Upload (Push to `gh-pages`)
`dpkg-deb --build pkgroot niri_version_amd64.deb` is run.
Then, the bot downloads your current repository (the `gh-pages` branch), copies the new `.deb` inside the `pool/main/` folder, regenerates the indices (`Packages`), cryptographically signs them with your private GPG key, and pushes the commit. All this in less than a minute!
