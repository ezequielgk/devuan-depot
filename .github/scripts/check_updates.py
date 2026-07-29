import urllib.request
import json
import os

CHECKS = [
    {"pkg": "niri", "type": "github_tag", "repo": "YaLTeR/niri"},
    {"pkg": "swayfx", "type": "github_tag", "repo": "WillPower3309/swayfx"},
    {"pkg": "concord", "type": "github_tag", "repo": "chojs23/concord"},
    {"pkg": "pcmanfm-qt", "type": "github_tag", "repo": "lxqt/pcmanfm-qt"},
    {"pkg": "foot", "type": "codeberg_tag", "repo": "dnkl/foot"},
    {"pkg": "xwayland-satellite", "type": "github_tag", "repo": "Supreeeme/xwayland-satellite"},
    {"pkg": "mangowc", "type": "github_commit", "repo": "mangowm/mango", "branch": "master"}
]

def get_repo_packages():
    url = "https://ezequielgk.github.io/devuan-depot/dists/trixie/main/binary-amd64/Packages"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            content = response.read().decode('utf-8')
    except Exception as e:
        print(f"Error fetching Packages: {e}")
        return {}

    packages = {}
    for block in content.strip().split("\n\n"):
        pkg, ver = None, None
        for line in block.split("\n"):
            if line.startswith("Package: "): pkg = line.split(": ")[1].strip()
            if line.startswith("Version: "): ver = line.split(": ")[1].strip()
        
        if pkg and ver:
            if pkg not in packages:
                packages[pkg] = []
            packages[pkg].append(ver)
    return packages

def get_github_latest_tag(repo, token):
    req = urllib.request.Request(f"https://api.github.com/repos/{repo}/tags")
    req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req) as response:
            tags = json.loads(response.read().decode('utf-8'))
            if tags:
                return tags[0]['name']
    except Exception as e:
        print(f"Error fetching tags for {repo}: {e}")
    return None

def get_codeberg_latest_tag(repo):
    req = urllib.request.Request(f"https://codeberg.org/api/v1/repos/{repo}/tags")
    try:
        with urllib.request.urlopen(req) as response:
            tags = json.loads(response.read().decode('utf-8'))
            if tags:
                return tags[0]['name']
    except Exception as e:
        print(f"Error fetching tags for {repo}: {e}")
    return None

def get_github_latest_commit(repo, branch, token):
    req = urllib.request.Request(f"https://api.github.com/repos/{repo}/commits/{branch}")
    req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req) as response:
            commit = json.loads(response.read().decode('utf-8'))
            return commit['sha']
    except Exception as e:
        print(f"Error fetching commits for {repo}: {e}")
    return None

def main():
    token = os.environ.get("GITHUB_TOKEN", "")
    current_packages = get_repo_packages()
    
    updates_found = []

    for check in CHECKS:
        pkg = check["pkg"]
        ctype = check["type"]
        repo = check["repo"]
        
        latest_version = None
        if ctype == "github_tag":
            latest_version = get_github_latest_tag(repo, token)
        elif ctype == "codeberg_tag":
            latest_version = get_codeberg_latest_tag(repo)
        elif ctype == "github_commit":
            branch = check.get("branch", "main")
            full_sha = get_github_latest_commit(repo, branch, token)
            if full_sha:
                latest_version = full_sha[:7] # short sha
                
        if not latest_version:
            continue
            
        # Clean the 'v' prefix for comparison if it's a tag
        clean_version = latest_version
        if clean_version.startswith("v") and any(c.isdigit() for c in clean_version):
            clean_version = clean_version[1:]
            
        # Check if any of the built versions for this package contain the clean_version
        built_versions = current_packages.get(pkg, [])
        is_built = False
        for bv in built_versions:
            if clean_version in bv:
                is_built = True
                break
                
        if not is_built:
            msg = f"- **{pkg}**: new version available (`{latest_version}`) in [{repo}](https://github.com/{repo})"
            if ctype == "codeberg_tag":
                msg = f"- **{pkg}**: new version available (`{latest_version}`) in [{repo}](https://codeberg.org/{repo})"
            updates_found.append(msg)
            
    if updates_found:
        print("Updates found!")
        for u in updates_found:
            print(u)
        
        # Write to GITHUB_ENV or GITHUB_OUTPUT so the workflow can create an issue
        with open(os.environ['GITHUB_OUTPUT'], 'a') as f:
            f.write("HAS_UPDATES=true\n")
            
        with open('updates.md', 'w') as f:
            f.write("New versions were found in the upstream repositories that have not yet been compiled in your repository:\n\n")
            for u in updates_found:
                f.write(f"{u}\n")
    else:
        print("No updates found.")
        with open(os.environ['GITHUB_OUTPUT'], 'a') as f:
            f.write("HAS_UPDATES=false\n")

if __name__ == "__main__":
    main()
