# Useful Scripts


## Project Overview

The **Useful Scripts** project is a collection of scripts designed to assist with various tasks. These scripts span multiple programming languages and environments, offering developers handy tools to automate routine operations, streamline workflows, and enhance productivity.


## Scripts

## Python Scripts
- **imgs_to_txt.py**: Perform OCR on images in a specified directory and output the recognized text to a single `.txt` file, supporting multiple languages.
- **pdf_to_imgs.py**: Convert a PDF file into images, allowing customization of image resolution and format.

## Shell Scripts
- **backup_home.sh**: A robust shell script for backing up your home directory, featuring options for file compression, exclusion, verification, and dry-run mode to simulate the backup process without any changes.
- **enable-emoji-support-for-arch.sh**: Enable emoji support on Arch-based Linux systems by installing emoji font packages and configuring fontconfig fallback. The script provides options for dry-run, verbose output, and selecting specific fonts to install.
- **fix-pacman-gpg.sh**: Fix pacman GPGME errors on Arch/Manjaro systems by clearing package metadata, reinitializing the pacman keyring, and optionally refreshing keys and updating the mirror list.
- **gpgkeys.sh**: Generate and manage GPG keys with interactive key generation, listing, exporting, deletion, backup/import, and GitHub integration. Supports ed25519 and rsa4096 algorithms, git signing configuration, and clipboard operations.
- **sshkeys.sh**: Generate and manage SSH keys with key generation, listing, deletion, ~/.ssh/config management (add/remove/list/show/edit/backup), and GitHub integration. Supports ed25519 and rsa key types, ssh-agent, clipboard operations, and interactive or scripted usage.
- **uninstall-jetbrains-toolbox.sh**: Uninstall JetBrains Toolbox from Linux systems, with optional removal of installed IDEs, configurations, and caches.


## Testing

Tests use [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

### Install dependencies (Arch)

```sh
sudo pacman -S bats bats-assert bats-support bats-file
```

### Run tests

```sh
# Run all tests
bats tests/

# Run a specific test file
bats tests/gpgkeys.bats

# Verbose output
bats --verbose-run tests/gpgkeys.bats
```
