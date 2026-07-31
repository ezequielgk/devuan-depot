# Update Checking System

In a software repository, keeping track of when the original developers release new versions is a heavy chore. To alleviate that, we created a watchful bot: the `check-updates.yml` workflow.

## The Bot's Architecture

The system consists of two parts:
1. The YAML file that tells GitHub when to run (Mondays and Thursdays at 08:00 UTC thanks to its `cron` command) and what permissions it has.
2. A Python script (`check_updates.py`) that is the "brain" of the operation.

## Why Python and not Bash?
Checking for updates involves connecting to the Internet, downloading information in JSON format (from APIs), filtering it, and comparing it with complex text. If we did this in a classic Bash script, it would be extremely fragile and hard to read. Python allows us to use libraries like `json` and `urllib` to do it cleanly and very precisely.

## How does `check_updates.py` work step-by-step?

### 1. Local Data Collection
The first thing the script does is download the `Packages` file from **your own web repository** (your `gh-pages` branch). It reads it and creates an internal dictionary in memory, knowing exactly which packages (and with which versions) you have compiled right now.

### 2. Searching the "Upstreams"
The script has an internal list (`CHECKS`) where we tell it which repositories to search in. For each of them, it connects to the corresponding API:
- **GitHub API:** For `Niri`, `SwayFX`, `Concord`, etc.
- **Codeberg API:** For `Foot`.
- In the case of `mangowc`, since they don't use formal version "Tags", it connects to the API to see what the **latest commit** of the `master` branch was.

### 3. The Precision Filter (Regular Expressions - Regex)
When you ask the GitHub API *"Give me the latest tag they uploaded"*, sometimes developers upload weird tags that aren't real versions (as happened with `split-libfm-qt` in pcmanfm-qt).
To avoid giving you false alarms, the script uses a strict **Regular Expression**: `^v?\d+(\.\d+)+`
This means: *"The tag must optionally start with a 'v', followed by a number, followed by at least one dot and another number"*.
Thanks to this mathematical filter, the script ignores fake tags and only captures real semantic versions (e.g., `2.4.0` or `v0.8.2`).

### 4. The Comparison
Once it has the newest and confirmed official version (e.g., `0.8.2`), it checks if that text **is contained** in the name of any of the versions you already have compiled.
If it doesn't find it, it deduces that you need to compile it, and notes it down in a list of pending updates.

### 5. Notification (Issue Creation)
If the list of pending updates is not empty, the script generates a temporary markdown file called `updates.md` and triggers a flag variable (`HAS_UPDATES=true`).
The GitHub Actions workflow detects that flag and uses the `peter-evans/create-issue-from-file` plugin to take that text and automatically open an **Issue** for you in the Issues tab of your repository.
And that's how the notification reaches your email!

## What to do when you receive an update notification?

When the bot opens an Issue notifying you of a new version (e.g., a new version of Niri), the process to update your repository is completely manual for security reasons. Just follow these 3 simple steps:

1. Go to the **Actions** tab in your repository on GitHub.
2. In the left sidebar, click on the compilation workflow corresponding to the package (for example, `Build Niri`).
3. Click the gray **"Run workflow"** button on the right side of the screen.

That's it! The workflow will automatically clone the new version, compile it, create the `.deb`, and upload it to your web repository. Once it finishes, you can close the Issue.
