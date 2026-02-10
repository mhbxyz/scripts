set shell := ["bash", "-uc"]

default:
    @just --list

# Installer les dépendances
sync:
    uv sync --all-groups

# Lancer les tests BATS
test:
    bats tests/

# Linter Python
lint:
    uv run ruff check python/

# Formatter Python
fmt:
    uv run ruff format python/

# Build un binaire localement
build script:
    #!/usr/bin/env bash
    case "{{script}}" in
        imgstotxt)  src="python/imgs_to_txt.py" ;;
        pdftoimgs)  src="python/pdf_to_imgs.py" ;;
        *)          echo "Unknown script: {{script}}"; exit 1 ;;
    esac
    uv run --group build pyinstaller --onefile --name "{{script}}" "$src"

# Build tous les binaires
build-all: (build "imgstotxt") (build "pdftoimgs")

# Lancer l'installeur localement
install *args:
    sh install.sh {{args}}
