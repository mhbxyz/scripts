<p align="center">
  <img src="assets/animated-banner.apng" alt="scripts:/$" />
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT" /></a>
  <img src="https://img.shields.io/badge/Shell-POSIX-green" alt="Shell" />
  <img src="https://img.shields.io/badge/Python-≥3.11-3776AB" alt="Python" />
  <a href="https://github.com/mhbxyz/scripts/actions/workflows/tests.yml"><img src="https://github.com/mhbxyz/scripts/actions/workflows/tests.yml/badge.svg" alt="Tests" /></a>
</p>

<p align="center"><em>A collection of shell and Python scripts to automate common tasks.</em></p>

## Install

```sh
curl -fsSL https://mhbxyz.github.io/scripts/install.sh | sh
```

```sh
sh -s -- --all                    # Install all scripts
sh -s -- --only "gpgkeys sshkeys" # Install specific scripts
sh -s -- update                   # Update installed scripts
sh -s -- uninstall                # Uninstall all scripts
```

See [docs/installation.md](docs/installation.md) for more details.

## Shell Scripts

| Script | Description |
|--------|-------------|
| `gpgkeys` | Generate and manage GPG keys |
| `sshkeys` | Generate and manage SSH keys |
| `homebackup` | Backup home directory to external drive |
| `sortdownloads` | Sort Downloads folder into organized subdirectories |
| `mygit` | Simplified git config management (requires `git`) |
| `dotfiles` | Manage dotfiles with symlinks |
| `mkproject` | Scaffold new projects from templates |
| `cleanup` | Free disk space by cleaning caches and temp files |

## Binary Scripts

Pre-compiled from Python, downloaded automatically from GitHub Releases.

| Script | Description |
|--------|-------------|
| `imgstotxt` | OCR images to text file |
| `pdftoimgs` | Convert PDF to images |

## Development

Requires [uv](https://docs.astral.sh/uv/) and [just](https://just.systems/).

```sh
just sync       # Install dependencies
just test        # Run BATS tests
just lint        # Lint Python with ruff
just fmt         # Format Python with ruff
just build-all   # Build all binaries with PyInstaller
```

See [docs/development.md](docs/development.md) for the full guide.

## License

[MIT](LICENSE)
