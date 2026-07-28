# Maintenance Cheat Sheet: devuan-depot

This document provides a quick reference for daily repository maintenance tasks and solutions for common issues encountered in GitHub Actions.

## Updating Packages

Most packages are automated to build the latest available code (the `main` branch or the latest `tag`).

### 1. Updating Applications or Libraries (e.g., mango, swayfx, wlroots)
When the upstream developer publishes new code and it needs to be reflected in `devuan-depot`:
1. Navigate to the repository on GitHub and open the **Actions** tab.
2. In the left sidebar, select the corresponding workflow (e.g., `Build MangoWC .deb`).
3. Click on **"Run workflow"** on the right side.
4. The GitHub Actions runner will clone the new code, build the `.deb` package with an updated hash, and publish it automatically.

### 2. Updating System Base Packages (Debian Backports)
To update packages such as `wayland`, `libdrm`, or `pixman` with the latest versions from Debian Sid:
1. Navigate to the **Actions** tab.
2. Select the **Build Debian Backports** workflow.
3. Click on **"Run workflow"**.

### 3. Forcing a Manual Update (Without Upstream Code Changes)
If a package needs to be rebuilt without new upstream commits (e.g., due to a change in the build dependencies within the `.yml` file), the upload will be cancelled by GitHub because the version string remains identical, leading `git commit` to detect "No changes".

To force a rebuild and upload, edit the corresponding `.yml` file and increment the `VERSION` variable.
For example, change:
```bash
VERSION="0.0.0+git${COMMIT_HASH}"
```
to:
```bash
VERSION="0.0.0+git${COMMIT_HASH}-2"
```

---

## Troubleshooting dpkg-shlibdeps

### The Empty `Depends:` Field Issue
If a `.deb` package compiles successfully, but the `Depends:` field is completely empty when running `apt-cache show <package>`, it indicates that `dpkg-shlibdeps` failed silently during the GitHub Actions workflow.

**The Cause:** 
Using the `find` command to pass binaries to `dpkg-shlibdeps` (e.g., `$(find pkgroot/usr/bin -type f -executable)`) can fail silently in Bash due to newline handling or error masking when multiple binaries or non-existent directories are encountered.

**The Solution:**
Do not use `find` inside command substitutions for dependencies. Explicitly target the exact path of the main binary of the application.

**Incorrect:**
```yaml
RAW_DEPS=$(dpkg-shlibdeps -O $(find pkgroot/usr/bin -type f -executable))
```

**Correct (Example for niri):**
```yaml
RAW_DEPS=$(dpkg-shlibdeps -O pkgroot/usr/bin/niri)
if [ $? -ne 0 ]; then
  echo "ERROR: dpkg-shlibdeps failed, check the log above"
  exit 1
fi
DEPS=$(echo "$RAW_DEPS" | sed 's/^shlibs:Depends=//')
```
