# Building and publishing devuan-depot

Operational reference for the CI/CD pipeline. For the high-level overview
and how to add a package, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Pipeline overview

```
workflow_dispatch
      │
      ▼
  build job  ──►  upload-artifact (.deb)
      │
      ▼
  publish job (needs: build)
      ├── checkout gh-pages
      ├── download-artifact → incoming/
      ├── find incoming -name '*.deb' -exec cp {} pool/main/ \;
      ├── dpkg-scanpackages --multiversion pool/ > Packages
      ├── apt-ftparchive release . >> Release
      ├── gpg sign → Release.gpg + InRelease
      └── git add pool dists && commit && push
      │
      ▼
  GitHub Pages serves the repo (~60–90s)
```

## Workflows

| Workflow | Package(s) | Source | Trigger |
|---|---|---|---|
| `build-mango.yml` | `mangowc` | upstream git main | manual |
| `build-wlroots.yml` | `wlroots0.19`, `wlroots0.20` | upstream tag (matrix) | manual |
| `build-scenefx.yml` | `scenefx0.4`, `scenefx0.5` | upstream branch (matrix) | manual |
| `build-swayfx.yml` | `swayfx` | upstream tag | manual |
| `build-concord.yml` | `concord` | upstream tag | manual |
| `build-foot.yml` | `foot` | upstream tag | manual |
| `build-niri.yml` | `niri` | upstream tag | manual |
| `build-pcmanfm-qt.yml` | `pcmanfm-qt` | upstream tag | manual |
| `build-xwayland-satellite.yml` | `xwayland-satellite` | upstream tag | manual + tag push |
| `build-backports.yml` | `libdrm`, `libwayland`, … | Debian sid source | manual |
| `cleanup-pool.yml` | — (maintenance) | — | manual |

## The `dpkg-shlibdeps-deps` composite action

Location: `.github/actions/dpkg-shlibdeps-deps/action.yml`

Resolves the `Depends:` field of a `.deb` by running `dpkg-shlibdeps`
against the freshly installed binaries. It writes the required
`debian/control` stub, runs the resolver, and **fails loudly** if the
returned `Depends:` is empty (the bug that shipped broken mangowc/swayfx
packages before this action existed).

### Inputs

| Input | Required | Description |
|---|---|---|
| `package-name` | yes | `Source`/`Package` name for the stub |
| `section` | yes | `Section` for the stub |
| `priority` | yes | `Priority` for the stub |
| `maintainer` | yes | `Maintainer` for the stub |
| `binaries` | one of these | Literal paths, space-separated |
| `find-expr` | one of these | `find(1)` args (without the `find` keyword) |
| `description-stub` | no | Short `Description` for the stub (default `stub`) |
| `working-directory` | no | Where to run (composite actions do NOT inherit the caller's `working-directory`) |

### Output

- `depends` — the resolved `Depends:` string, ready for `${{ steps.deps.outputs.depends }}`

### Gotchas

- **Composite actions do not inherit `working-directory`.** Pass it as
  an input and apply it to every internal `run:` step.
- **Do not put `${{ steps.*... }}` in `outputs.<id>.description`.**
  GitHub template-evaluates that string and rejects the `steps` context.
  Plain text only.
- **`find-expr` starting points that do not exist are skipped with a
  warning**, and the action only fails if none of them exist.

## The publish step

```bash
# 1. Collect every .deb recursively (download-artifact may nest them).
find incoming -type f -name '*.deb' -exec cp -v {} pool/main/ \;

# 2. Guard: abort if nothing was copied.
if ! ls pool/main/*.deb >/dev/null 2>&1; then
  echo "::error::no .deb files were copied"; exit 1
fi

# 3. Regenerate the index with --multiversion so apt sees every version.
dpkg-scanpackages --arch amd64 --multiversion pool/ \
  > dists/trixie/main/binary-amd64/Packages
gzip -9fk dists/trixie/main/binary-amd64/Packages

# 4. Refresh Release with current hashes + Date, then sign it.
cd dists/trixie
apt-ftparchive release . >> Release
gpg --default-key "$GPG_KEY_ID" -abs -o Release.gpg Release
gpg --default-key "$GPG_KEY_ID" --clearsign -o InRelease Release

# 5. Commit and push to gh-pages.
git add pool dists
git commit -m "Update <pkg>" || echo "No changes"
git push
```

### Why `find` and not `cp incoming/*.deb`

`actions/download-artifact@v4` with `pattern:` + `merge-multiple: true`
nests each artifact under its own subdirectory
(`incoming/<artifact-name>/<file>.deb`), so `incoming/*.deb` matches
nothing. Using `find incoming -name '*.deb'` collects them regardless of
nesting.

### Why `--multiversion`

Without it, `dpkg-scanpackages` keeps only one `.deb` per package name,
picked by scan order (alphabetical filename), **not** by Debian version
comparison. An older build with an alphabetically larger filename then
shadows a newer one. `--multiversion` writes every version into
`Packages`; apt's own version logic picks the highest.

### The `.gitignore` exception

The repo-root `.gitignore` has `*.deb` (to ignore local build artifacts)
which would also exclude `pool/main/*.deb` from git. The exception
`!pool/main/*.deb` re-includes them. Without it, `git add pool` silently
skips the new `.deb` files and the commit only touches `dists/`,
publishing a `Packages` that references a `.deb` that was never
committed.

## Versioning: why the date comes first

`dpkg --compare-versions` is lexicographic per component. A git short
hash like `9ce833b` sorts *lower* than `cc4fdec` (because `9` < `c` in
ASCII), so a newer build with a `9…` hash would lose to an older `c…`
build. Putting the date as the second component fixes this:

```
0.20260728+git9ce833b.5~devuandepot   >   0.0.0+gitcc4fdec
        ▲
        └── 20260728 > 0, comparison stops here
```

The `~devuandepot` suffix marks the package as a pre-release snapshot,
keeping it below any future upstream release occupying the same
version slot.

## Cleanup workflow (`cleanup-pool.yml`)

Over time `pool/main/` accumulates one `.deb` per re-run of every
workflow. The cleanup workflow prunes old versions and regenerates the
signed index.

### Inputs

| Input | Default | Description |
|---|---|---|
| `keep-count` | `2` | Number of versions to keep per package (highest ones win). `1` = only the latest. |
| `dry-run` | `true` | If `true`, only prints what would be removed. If `false`, actually deletes, regenerates `Packages`/`Release`/`InRelease`, and pushes to `gh-pages`. |
| `packages` | (empty) | Comma-separated package names to restrict cleanup to. Empty = all packages that ship a `~devuandepot` suffix. |

### What it touches

Only files whose name contains `~devuandepot`. Debian sid backports
(`libdrm`, `libwayland`, …) are left untouched because they keep the
upstream version.

### Recommended usage

1. **Dry-run first** — set `dry-run: true` and review the `KEEP`/`DROP`
   list in the run log.
2. **Execute** — set `dry-run: false` with the same `keep-count`.

```
keep-count: 2
dry-run:    true
packages:   (empty)
```

The workflow groups `.deb` files by their `Package` control field, sorts
each group with `dpkg --compare-versions`, keeps the top `keep-count`
and `git rm`s the rest. After deleting it regenerates `Packages` with
`--multiversion`, re-signs `Release`/`InRelease`, commits, and pushes.

## Operational playbook

### Re-running the build chain

Dependencies cascade, so run in this order (wait ~90s between each for
GitHub Pages to serve the new index):

1. `Build wlroots .deb` → publishes `wlroots0.19` + `wlroots0.20`
2. `Build scenefx .deb` → publishes `scenefx0.4` + `scenefx0.5`
3. `Build MangoWC .deb` → depends on `wlroots0.20` + `scenefx0.5`
4. `Build SwayFX .deb` → depends on `wlroots0.19` + `scenefx0.4`
5. `Build PCManFM-Qt`, `Build concord`, `Build foot`, `Build niri`,
   `Build xwayland-satellite` — independent, run in any order
6. `Cleanup gh-pages pool` → prune old `.deb` versions

### Verifying a publish

```bash
# Does the Packages file list the new version with Depends populated?
curl -fsSL https://ezequielgk.github.io/devuan-depot/dists/trixie/main/binary-amd64/Packages \
  | awk '/^Package: <pkg>$/,/^$/' | grep -E '^(Version|Depends):'

# Does apt see it?
sudo apt update
apt-cache policy <pkg>
sudo apt-get install --dry-run <pkg>
```

## Secrets

| Secret | Used for |
|---|---|
| `GPG_PRIVATE_KEY` | Importing the signing key in the publish job |
| `GPG_PASSPHRASE` | Unlocking the key above |
| `GPG_KEY_ID` | Selecting the subkey to sign `Release`/`InRelease` |

The matching public key is distributed at
<https://ezequielgk.github.io/devuan-depot/public.asc>.