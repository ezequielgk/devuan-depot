# Repository Maintenance and Cleanup

If you compile new packages every day, the `pool/main/` folder would fill up with hundreds of old `.deb` files. GitHub Pages has a strict limit of **1 Gigabyte** of storage per repository. If you exceed that limit, the webpage and the APT repository would stop working.

To prevent this, we implemented the cleanup workflows: `cleanup-pool.yml` and `cleanup-backports.yml`.

## How do the cleanup scripts work?

These workflows do not compile anything; their only job is to manage the existing files in the `gh-pages` branch.

### The retention logic
Inside the YAML file, there is a miniature Python script that does the following:
1. **Scans the `pool/main/` folder** and finds all `.deb` files.
2. **Groups packages by name.** For example, it gathers all the versions of `niri` it finds into the same list.
3. **Sorts the versions.** Using Debian's versioning logic, it sorts the Niri list from the oldest version to the newest (thanks to us adding the date and build number in the previous step).
4. **Deletes the excess.** If you told it to retain `keep: 1` in the configuration, the script will spare the highest version (the 1 most recent) and will do a `git rm` (delete) to absolutely all the other old versions. If you put `keep: 3`, it will keep the last 3 and delete the rest.

### The Specific Files
- **`cleanup-pool.yml`:** Cleans the main packages of your repository (those with the `~devuandepot` label). It is configured to trigger automatically, or you can run it manually.
- **`cleanup-backports.yml`:** Cleans the "base" packages or libraries that you compile (like `libwayland`, `pixman`, etc.). On these, we usually don't put the `~devuandepot` label so as not to break Debian's naming convention, but the script works exactly the same.
- **`cleanup-legacy.yml`:** Was a one-time temporary workflow that we created to purge old versions that you compiled in the past and that didn't have the modern naming standard. Once executed, it has already served its purpose.

### Index Reconstruction
Once the Python script deletes the old `.deb` files, the job doesn't end there.
If we left the repository like that, the user running `apt update` would see an error because the master `Packages` file on your server would still list the deleted packages.

Therefore, the second part of the workflow runs the packaging tools again:
```bash
dpkg-scanpackages --arch amd64 --multiversion pool/ > dists/trixie/main/binary-amd64/Packages
gzip -9fk dists/trixie/main/binary-amd64/Packages
```
This scans the real (now clean) `pool/` folder, generates a fresh new index, signs it again with GPG, and uploads it. That's why your repository never gets corrupted!
