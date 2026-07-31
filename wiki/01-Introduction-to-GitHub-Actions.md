# Introduction to GitHub Actions

To understand how your repository works, you first need to understand what **GitHub Actions** is. It is an integrated service in GitHub that allows you to automate tasks (like compiling code, running tests, or publishing files) directly on GitHub's servers, for free.

## Key Concepts

### 1. Workflows
A **Workflow** is an automated process. In your repository, every file that ends in `.yml` inside the `.github/workflows/` folder is a distinct workflow.
Think of a workflow as a script that tells GitHub: *"When X happens, run Y commands"*.

### 2. Runs
Every time a workflow is triggered and starts working, it is called a **Run**.
- If you go to the "Actions" tab on GitHub, you will see a list of the history of all the *runs*.
- Each *run* shows you a detailed line-by-line log of what happened during that execution, which is vital if something fails and you need to see why.

### 3. Triggers
These are the events that tell a workflow when it should start. In your repository, we primarily use two types of *triggers*, which are defined under the `on:` keyword:
- **`workflow_dispatch`:** Means the workflow **will only run when you manually request it**. To use it, you go to the "Actions" tab, select the workflow on the left, and press the *"Run workflow"* button. It is ideal for delicate tasks like compiling a package or deleting something.
- **`schedule`:** Means the workflow has an internal clock based on **cron** (a standard Linux tool for scheduled tasks). For example, the update checker workflow has a cron of `0 8 * * 1,4`, which means it starts on its own automatically every Monday and Thursday at 08:00 UTC.

### 4. Runners (The Virtual Machine)
When a workflow starts, GitHub "spins up" a temporary and free virtual machine in the cloud to execute your commands.
In most of your files, you will see `runs-on: ubuntu-latest`. This means GitHub lends you a freshly installed Ubuntu PC.
**Important fact:** That machine is ephemeral! It is born empty when the *run* starts and is completely destroyed when it finishes. If you generate a file and don't save or upload (push) it, it is lost forever.

### 5. Containers (Docker)
Although GitHub gives us Ubuntu, the packages in your repository are designed for **Devuan Trixie**. If we compiled SwayFX directly on Ubuntu, the libraries would be different, and the `.deb` package would fail on a user's computer.
Therefore, inside the Runner, we define a `container: image: debian:trixie`. This causes the workflow to download a clean Debian/Devuan Trixie image and execute all your commands inside that bubble, ensuring total compatibility.

### 6. Secrets
Since your repository is public, anyone can see the code of your workflows. But you need real passwords (like your GPG key) to sign the packages.
That's what **Secrets** are for. They are encrypted environment variables that you configured in the repository options. When a script sees `${{ secrets.GPG_PASSPHRASE }}`, GitHub injects your real password behind the scenes, but hides it with asterisks (`***`) in the logs so no one can steal it.
