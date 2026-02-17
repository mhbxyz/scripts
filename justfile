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
    uv run ruff check src/python/

# Formatter Python
fmt:
    uv run ruff format src/python/

# Build un binaire localement
build script:
    #!/usr/bin/env bash
    common="--onefile --strip"
    exclude_base="tkinter,_tkinter,PIL.ImageTk,unittest,test,pydoc,doctest,email,html,http,xmlrpc,xml.etree,multiprocessing,concurrent,asyncio,logging,csv,sqlite3,decimal,fractions,pdb,profile,cProfile,trace,ensurepip,venv,pip,setuptools,lib2to3,idlelib,distutils,turtledemo,turtle"
    case "{{script}}" in
        keepalive)
            src="src/python/keep_alive.py"
            excludes="$exclude_base,PIL,pytesseract,fitz,pymupdf" ;;
        imgstotxt)
            src="src/python/imgs_to_txt.py"
            excludes="$exclude_base,fitz,pymupdf" ;;
        pdftoimgs)
            src="src/python/pdf_to_imgs.py"
            excludes="$exclude_base,PIL.ImageTk,pytesseract" ;;
        *)
            echo "Unknown script: {{script}}"; exit 1 ;;
    esac
    exclude_flags=""
    IFS=',' read -ra mods <<< "$excludes"
    for mod in "${mods[@]}"; do
        exclude_flags+=" --exclude-module $mod"
    done
    uv run --group build pyinstaller $common --name "{{script}}" $exclude_flags "$src"

# Build tous les binaires
build-all: (build "imgstotxt") (build "pdftoimgs") (build "keepalive")

# Générer docs/versions depuis les sources
versions:
    #!/usr/bin/env bash
    set -euo pipefail
    declare -A src=(
        [imgstotxt]="src/python/imgs_to_txt.py"
        [pdftoimgs]="src/python/pdf_to_imgs.py"
        [keepalive]="src/python/keep_alive.py"
    )
    out="docs/versions"
    : > "$out"
    for f in src/shell/*.sh; do
        name=$(basename "$f" .sh)
        ver=$(grep '^VERSION=' "$f" | cut -d'"' -f2)
        printf '%s|%s\n' "$name" "$ver" >> "$out"
    done
    for name in "${!src[@]}"; do
        ver=$(grep '^__version__' "${src[$name]}" | cut -d'"' -f2)
        printf '%s|%s\n' "$name" "$ver" >> "$out"
    done
    sort -o "$out" "$out"
    echo "Generated $out ($(wc -l < "$out") entries)"

# Lancer l'installeur localement
install *args:
    sh docs/install.sh {{args}}
