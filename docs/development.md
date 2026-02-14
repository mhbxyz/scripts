# Development

## Prerequisites

- [uv](https://docs.astral.sh/uv/) — Python package manager
- [just](https://just.systems/) — command runner
- [bats](https://bats-core.readthedocs.io/) — Bash test framework (with bats-support, bats-assert, bats-file)

## Setup

```sh
just sync
```

Installs all Python dependencies (main, dev, and build groups).

## Tests

```sh
just test
```

Runs all BATS test suites in `tests/`.

## Lint and format

```sh
just lint    # Check Python code with ruff
just fmt     # Format Python code with ruff
```

## Build binaries locally

```sh
just build imgstotxt     # Build a single binary
just build pdftoimgs
just build-all           # Build all binaries
```

Binaries are output to `dist/`.

## Release

Each Python script is versioned and released independently using prefixed tags.

### Tag format

```
<script>-v<semver>
```

Examples: `imgstotxt-v1.0.0`, `pdftoimgs-v1.2.0`

### Creating a release

```sh
git tag imgstotxt-v1.0.0
git push --tags
```

The CI workflow will:
1. Parse the tag to identify the script and version
2. Build binaries for Linux x86_64, macOS x86_64, and macOS arm64
3. Create a versioned GitHub release (`imgstotxt-v1.0.0`)
4. Update the floating `imgstotxt-latest` release used by the installer

## Project structure

```
.
├── src/
│   ├── shell/              # Shell scripts
│   └── python/             # Python scripts
├── tests/                  # BATS test suites
│   ├── mocks/              # Mock binaries for tests
│   ├── test_helper.bash    # Shared test helpers
│   ├── install.bats        # Installer tests
│   └── *.bats              # Per-script tests
├── docs/                   # Documentation + installer
│   └── install.sh          # Installer script
├── .github/workflows/      # CI workflows
│   ├── tests.yml           # Test + lint on push/PR
│   └── release.yml         # Build + release on tag
├── pyproject.toml          # Python project config (uv)
└── justfile                # Development recipes
```

## Adding a new script

### Shell script

1. Add the script to `src/shell/`
2. Add an entry to `MANIFEST` in `install.sh` with type `shell`
3. Add tests in `tests/`
4. Update `setup_install_env()` in `tests/test_helper.bash`

### Python binary

1. Add the script to `src/python/`
2. Add dependencies to `pyproject.toml`
3. Add a `case` entry in the `justfile` `build` recipe
4. Add an entry to `MANIFEST` in `install.sh` with type `binary` and a release tag
5. Add the script name to the `case` in `.github/workflows/release.yml` (prepare job)
6. Add the tag pattern to the `on.push.tags` array in `release.yml`
7. Add mock binaries in `setup_install_env()` in `tests/test_helper.bash`
8. Add tests in `tests/`
