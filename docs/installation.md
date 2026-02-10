# Installation

## Quick install

```sh
curl -fsSL https://raw.githubusercontent.com/mhbxyz/scripts/main/install.sh | sh
```

This opens an interactive menu to select which scripts to install.

## Options

```sh
# Install all scripts
curl -fsSL .../install.sh | sh -s -- --all

# Install specific scripts only
curl -fsSL .../install.sh | sh -s -- --only "gpgkeys sshkeys"

# Install to a custom directory
curl -fsSL .../install.sh | sh -s -- --all --dir ~/bin
```

## Available scripts

### Shell scripts

Downloaded from the repository source.

| Name | Description |
|------|-------------|
| `gpgkeys` | Generate and manage GPG keys |
| `sshkeys` | Generate and manage SSH keys |
| `homebackup` | Backup home directory to external drive |
| `sortdownloads` | Sort Downloads folder into organized subdirectories |

### Binary scripts

Pre-compiled binaries downloaded from GitHub Releases. Supported platforms: Linux x86_64, macOS x86_64, macOS arm64.

| Name | Description |
|------|-------------|
| `imgstotxt` | OCR images to text file |
| `pdftoimgs` | Convert PDF to images |

## System dependencies

| Script | Dependency | Install |
|--------|-----------|---------|
| `imgstotxt` | `tesseract-ocr` | `sudo apt install tesseract-ocr` (Debian/Ubuntu) or `sudo pacman -S tesseract` (Arch) |

## Update

```sh
curl -fsSL .../install.sh | sh -s -- update
```

Re-downloads all currently installed scripts.

## Uninstall

```sh
# Remove all scripts
curl -fsSL .../install.sh | sh -s -- uninstall --all

# Remove specific scripts
curl -fsSL .../install.sh | sh -s -- uninstall --only "gpgkeys"
```
