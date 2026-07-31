# Deployment with GitHub Pages

Your repository serves a dual purpose. On the one hand, it is an **APT Repository** (from which Linux terminals download software), and on the other hand, it is a beautiful **Webpage** (your `index.html`).
Both things are served to the public through the same free server: **GitHub Pages**.

## The problem with the classic method
In the past, people would go to the repository options and check "Deploy from the gh-pages branch". This meant that every time you uploaded a new `.deb`, GitHub would take several minutes to detect the change, internally compile the entire page with Jekyll, and only then publish it. Sometimes it failed, sometimes it got stuck.

## The modern solution: `deploy-pages.yml`

To have absolute control and ensure your package updates are instantaneous, we created this workflow.

### How does it work?
Instead of relying on GitHub to build the page automatically, we tell GitHub: *"Disable your automatic system, I'll take care of uploading the final files"*.

The `deploy-pages.yml` file has the configuration `on: push: branches: ["gh-pages"]`.
This means that **every time** one of your compilation or cleanup workflows modifies the `gh-pages` branch (by uploading a new `.deb` or deleting an old one), this workflow is triggered instantly.

1. It uses the `actions/configure-pages@v5` plugin to authenticate with the Pages server.
2. It uses `actions/upload-pages-artifact@v3` to literally grab **all** the current content of the `gh-pages` branch (your `dists/`, `pool/` folders, and your `index.html`) and package it into an ultra-fast ZIP called an "Artifact".
3. It uses `actions/deploy-pages@v4` to inject that ZIP directly into GitHub's web servers.

### Advantages of this system
- **Speed:** The deployment of your webpage and updated packages takes less than 10 seconds to reflect globally, compared to the minutes the old method took.
- **Security:** There are no weird compilers in the middle breaking your files. What is in your `gh-pages` branch is *exactly* the same as what users will download, byte for byte.

## The Web Frontend (`index.html`)
The webpage we built is dynamic. Inside, it has JavaScript code that automatically fetches and reads your `Packages` index file (which the bot updates when it compiles).
The web "parses" that file, detects which packages you have and what their latest versions are, and paints interactive colored cards for the user. Therefore, you never have to edit the HTML by hand when you upload a new program! Everything syncs itself.
