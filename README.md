# Laravel DDEV Setup Script

> **Note:** This setup script was developed and tested on **macOS**.  
> It should also work on Linux with minor or no modifications.  
> Windows users may encounter compatibility issues with certain commands (e.g. `open`, file paths, or shell syntax).

---

This repository contains a Bash script to automate the setup of a new Laravel project using **DDEV**. It installs Laravel, Node dependencies, Tailwind CSS, Prettier, and sets up extra DDEV web ports. The script is modular and provides color-coded logging.

---

## Prerequisites

Make sure the following tools are installed on your host machine:

- [DDEV](https://ddev.com/)
- [Docker](https://www.docker.com/)
- [jq](https://stedolan.github.io/jq/)
- `open` (macOS) or equivalent
- `lsof`

If these are missing the script stops running.
---

## Usage

1. **Go to script directory and make the script executable**:

```bash
cd laravel-setup && chmod +x setup_laravel.sh
```

2. **Run the setup script**:

```bash
BASE_DIR=/path/to/projects PROJECT_NAME=my-custom-app setup_laravel.sh
```

## QoL Scripts

1. **To format with Prettier plugin run this inside your project files**:

```bash
ddev npm run format
```

2. **To to update IDE Helpers run this inside your project files**:

```bash
ddev npm run helpers
```


What the Script Does
--------------------

The script performs the following steps:

1.  **Check host dependencies** – Ensures required tools are installed.
    
2.  **Clean project** – Stops any existing DDEV project with the same name and cleans the directory.
    
3.  **Create DDEV project** – Configures Laravel project with DDEV and starts containers.
    
4.  **Wait for web container** – Waits until the web container becomes healthy.
    
5.  **Install container tools** – Installs jq, npm, and php inside the container if missing.
    
6.  **Install Laravel** – Sets up a fresh Laravel project inside DDEV.
    
7.  **Ensure package.json** – Creates a default package.json if it doesn’t exist.
    
8.  **Install Node dependencies** – Installs Tailwind CSS, PostCSS, Prettier, and related plugins.

9. **Install Laravel IDE Helper** - Installs the [barryvdh/laravel-ide-helper](https://github.com/barryvdh/laravel-ide-helper) package
    
9.  **Append DDEV extra web ports** – Adds extra ports for Node/Vite if not already present.
    
10.  **Replace Vite config** – Replaces vite.config.js with your resource version.
    
11.  **Apply patches** – Optionally applies patches like Prettier config.
    
12.  **Final cleanup** – Removes temporary files and scaffolds.
    
13.  **Summary** – Prints successful and failed steps.

License
-------

This setup script is provided as-is. Modify it freely for your projects.
