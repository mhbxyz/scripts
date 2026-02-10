# Scripts

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Shell](https://img.shields.io/badge/Shell-POSIX-green)
![Tests](https://img.shields.io/badge/Tests-BATS-yellow)

A collection of shell and Python scripts to automate common tasks.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/mhbxyz/scripts/main/install.sh | sh
```

```sh
sh -s -- --all                    # Install all scripts
sh -s -- --only "gpgkeys sshkeys" # Install specific scripts
sh -s -- update                   # Update installed scripts
sh -s -- uninstall                # Uninstall all scripts
```

## Shell Scripts

| Script | Description |
|--------|-------------|
| `gpgkeys` | Generate and manage GPG keys |
| `sshkeys` | Generate and manage SSH keys |
| `homebackup` | Backup home directory to external drive |
| `fix-pacman-gpg` | Fix pacman GPG errors on Arch/Manjaro |
| `enable-emoji-support-for-arch` | Enable emoji support on Arch |
| `uninstall-jetbrains-toolbox` | Uninstall JetBrains Toolbox |

## Python Scripts

| Script | Description |
|--------|-------------|
| `imgs_to_txt` | OCR images to text file |
| `pdf_to_imgs` | Convert PDF to images |

> Python scripts are not covered by the curl installer.

## Testing

Tests use [BATS](https://github.com/bats-core/bats-core). Install with `sudo pacman -S bats bats-assert bats-support bats-file`, then:

```sh
bats tests/
```

## License

[MIT](LICENSE)
