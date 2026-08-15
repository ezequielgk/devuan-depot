# GitHub Actions Workflows Guide

This document explains the correct order in which the GitHub Actions workflows must be executed to ensure all dependencies are built correctly and the repository works flawlessly.

## Build Order

Since some packages depend on others to build or run, it is **critical** to follow this order if you are rebuilding the repository from scratch or dealing with massive updates.

### 1. Base Libraries (Backports)
**Workflow:** `Build Libraries` -> Select package: `backports`
Backports (`wayland`, `libdrm`, `pixman`, etc.) are the foundation of the system. Many modern packages require recent versions of these libraries that are not found in the stable version of Devuan/Debian. They must be compiled and published first so they are available in the build environment for the subsequent packages.

### 2. Core Libraries (Wayland)
**Workflow:** `Build Libraries`
These are the Wayland-specific libraries used by the compositors.
- Select: `wlroots`
- Select: `scenefx` (Depends on wlroots)
- Select: `xwayland-satellite` (Independent, but useful to build here)

### 3. Window Managers (Compositors)
**Workflow:** `Build Window Managers`
Once `wlroots`, `scenefx`, and the `backports` are published in the `gh-pages` repository, window managers can compile properly by fetching them via `apt`.
- Select: `mangowc`
- Select: `noctalia`
- Select: `swayfx`

### 4. Applications
**Workflow:** `Build Apps`
Applications are usually the leaves in the dependency tree, so they can be compiled at the end or completely independently at any time.
- Select: `foot`
- Select: `gamescope`
- Select: `mullvad-libre`
- Select: `portproton`

---

## Maintenance Workflows

Maintenance workflows do not build packages, but rather keep the `apt` repository healthy.

### `Maintenance: Check Upstream Updates`
- **Usage:** Runs automatically (via cron schedule) on Mondays and Thursdays.
- **Function:** Runs a Python script that checks the GitHub APIs for new tags of the original packages. If updates are found, it creates an "Issue" in the repository notifying you so you can trigger the corresponding Build.

### `Maintenance: Cleanup Repository`
- **Usage:** Manual. Run this when the repository pool starts taking up too much space or there are too many old versions.
- **Function:** Analyzes the published `.deb` files. It allows you to choose whether to clean the pool (`~devuandepot`), legacy files (orphaned packages without the suffix), or backports (upstream sid). By default, it keeps the last 2 versions and deletes the rest. Always use `dry-run: true` first to verify what will be deleted.

### `Maintenance: Force Regenerate Indices`
- **Usage:** Manual. For emergencies only.
- **Function:** If a user ever reports errors like *Hash Sum mismatch* or *404 Not Found* when running `apt-get update`, execute this workflow. It will re-scan all existing `.deb` files and rebuild the `Packages`, `Release`, and `InRelease` files, signing them with your GPG key.

### `System: Deploy GitHub Pages`
- **Usage:** Automatic.
- **Function:** Whenever one of the Build or Maintenance workflows does a `git push` to the `gh-pages` branch, GitHub runs this workflow in the background to publish the static files so they are accessible via the web (for `apt`). You do not need to touch this.
