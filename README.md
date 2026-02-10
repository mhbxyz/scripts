<pre>
███████╗ ██████╗██████╗ ██╗██████╗ ████████╗███████╗
██╔════╝██╔════╝██╔══██╗██║██╔══██╗╚══██╔══╝██╔════╝
███████╗██║     ██████╔╝██║██████╔╝   ██║   ███████╗
╚════██║██║     ██╔══██╗██║██╔═══╝    ██║   ╚════██║
███████║╚██████╗██║  ██║██║██║        ██║   ███████║
╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝╚═╝        ╚═╝   ╚══════╝
</pre>

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Shell](https://img.shields.io/badge/Shell-POSIX-green)
![Python](https://img.shields.io/badge/Python-≥3.11-3776AB)
[![Tests](https://github.com/mhbxyz/scripts/actions/workflows/tests.yml/badge.svg)](https://github.com/mhbxyz/scripts/actions/workflows/tests.yml)

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

See [docs/installation.md](docs/installation.md) for more details.

## Shell Scripts

| Script | Description |
|--------|-------------|
| `gpgkeys` | Generate and manage GPG keys |
| `sshkeys` | Generate and manage SSH keys |
| `homebackup` | Backup home directory to external drive |
| `sortdownloads` | Sort Downloads folder into organized subdirectories |

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
