#!/bin/sh

# Scaffold new projects from templates
# Author: Manoah Bernier

set -eu

VERSION="1.0.0"

# ── Colors ──

RESET="\033[0m"
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"

# ── Temp file cleanup ──

TMPFILES=""

cleanup() {
  for f in $TMPFILES; do
    rm -f "$f"
  done
}

trap cleanup EXIT INT TERM

register_tmp() {
  TMPFILES="$TMPFILES $1"
}

# ── Utility functions ──

die() {
  printf "${RED}❌ %s${RESET}\n" "$*" >&2
  exit 1
}

warn() {
  printf "${YELLOW}⚠️  %s${RESET}\n" "$*" >&2
}

info() {
  printf "${BLUE}%s${RESET}\n" "$*"
}

success() {
  printf "${GREEN}✅ %s${RESET}\n" "$*"
}

check_dep() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found. Please install it."
}

# ── License templates ──

license_mit() {
  _year=$(date +%Y)
  cat <<EOF
MIT License

Copyright (c) $_year $1

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
}

license_apache() {
  _year=$(date +%Y)
  cat <<EOF
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   Copyright $_year $1

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
EOF
}

license_gpl3() {
  _year=$(date +%Y)
  cat <<EOF
Copyright (C) $_year $1

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
EOF
}

write_license() {
  _type="$1" _author="$2" _dest="$3"
  case "$_type" in
    MIT)        license_mit "$_author" > "$_dest" ;;
    Apache-2.0) license_apache "$_author" > "$_dest" ;;
    GPL-3.0)    license_gpl3 "$_author" > "$_dest" ;;
    none)       return 0 ;;
    *)          die "Unknown license type: $_type. Use MIT, Apache-2.0, GPL-3.0, or none." ;;
  esac
}

write_readme() {
  _name="$1" _dest="$2"
  cat > "$_dest" <<EOF
# $_name

## Usage

## License
EOF
}

# ── Gitignore templates ──

gitignore_sh() {
  cat <<'EOF'
*.swp
*.swo
*~
EOF
}

gitignore_python() {
  cat <<'EOF'
__pycache__/
*.py[cod]
*$py.class
*.egg-info/
dist/
build/
.venv/
*.egg
EOF
}

gitignore_go() {
  cat <<'EOF'
/bin/
*.exe
*.test
*.out
EOF
}

gitignore_web() {
  cat <<'EOF'
node_modules/
.DS_Store
*.swp
EOF
}

gitignore_generic() {
  cat <<'EOF'
*.swp
*~
.DS_Store
EOF
}

# ── Template scaffolders ──

scaffold_sh() {
  _name="$1" _dir="$2"
  cat > "$_dir/$_name.sh" <<EOFSH
#!/bin/sh
set -eu

echo "Hello from $_name"
EOFSH
  chmod +x "$_dir/$_name.sh"

  mkdir -p "$_dir/tests"
  cat > "$_dir/tests/$_name.bats" <<EOFBATS
#!/usr/bin/env bats

@test "$_name runs" {
  run ./$_name.sh
  [ "\$status" -eq 0 ]
}
EOFBATS

  cat > "$_dir/Makefile" <<'EOFMAKE'
.PHONY: test lint

test:
	bats tests/

lint:
	shellcheck *.sh
EOFMAKE
  gitignore_sh > "$_dir/.gitignore"
}

scaffold_python() {
  _name="$1" _dir="$2"
  mkdir -p "$_dir/src/$_name" "$_dir/tests"
  printf '' > "$_dir/src/$_name/__init__.py"
  printf '' > "$_dir/tests/__init__.py"

  cat > "$_dir/pyproject.toml" <<EOFTOML
[project]
name = "$_name"
version = "0.1.0"
requires-python = ">=3.11"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
EOFTOML
  gitignore_python > "$_dir/.gitignore"
}

scaffold_go() {
  _name="$1" _dir="$2"
  cat > "$_dir/main.go" <<EOFGO
package main

import "fmt"

func main() {
	fmt.Println("Hello from $_name")
}
EOFGO

  cat > "$_dir/go.mod" <<EOFMOD
module $_name

go 1.21
EOFMOD

  cat > "$_dir/Makefile" <<EOFMAKE
.PHONY: build test run

build:
	go build -o bin/$_name .

test:
	go test ./...

run:
	go run .
EOFMAKE
  gitignore_go > "$_dir/.gitignore"
}

scaffold_web() {
  _name="$1" _dir="$2"
  mkdir -p "$_dir/css" "$_dir/js"

  cat > "$_dir/index.html" <<EOFHTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$_name</title>
  <link rel="stylesheet" href="css/style.css">
</head>
<body>
  <h1>$_name</h1>
  <script src="js/main.js"></script>
</body>
</html>
EOFHTML

  cat > "$_dir/css/style.css" <<'EOFCSS'
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}
EOFCSS

  cat > "$_dir/js/main.js" <<'EOFJS'
// main.js
EOFJS
  gitignore_web > "$_dir/.gitignore"
}

scaffold_generic() {
  _dir="$1"
  gitignore_generic > "$_dir/.gitignore"
}

# ── Help ──

show_help() {
  prog=$(basename "$0")
  cat <<EOF
$prog – Scaffold new projects from templates

Usage:
  $prog <template> <name> [options]
  $prog list
  $prog help

Templates:
  sh        Shell script project
  python    Python project with pyproject.toml
  go        Go project with go.mod
  web       Static web project
  generic   Minimal project (README + LICENSE)

Options:
  --no-git             Do not initialize a git repository
  --no-readme          Do not create README.md
  --license <type>     License type: MIT (default), Apache-2.0, GPL-3.0, none
  --author <name>      Author name (default: git config user.name or \$USER)

Examples:
  $prog sh myutil
  $prog python myapp --license Apache-2.0
  $prog go myapi --no-git
  $prog web mysite --author "John Doe"
  $prog generic myproject --license none
  $prog list
EOF
  exit 0
}

# ── Commands ──

cmd_list() {
  cat <<'EOF'
Available templates:
  sh        Shell script project
  python    Python project with pyproject.toml
  go        Go project with go.mod
  web       Static web project
  generic   Minimal project (README + LICENSE)
EOF
}

cmd_create() {
  _template="$1"; shift
  [ $# -ge 1 ] || die "Missing project name. Usage: mkproject <template> <name>"
  _name="$1"; shift

  _no_git=0
  _no_readme=0
  _license="MIT"
  _author=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --no-git)    _no_git=1; shift ;;
      --no-readme) _no_readme=1; shift ;;
      --license)
        [ $# -ge 2 ] || die "--license requires an argument"
        _license="$2"; shift 2 ;;
      --author)
        [ $# -ge 2 ] || die "--author requires an argument"
        _author="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  # Resolve author
  if [ -z "$_author" ]; then
    _author=$(git config user.name 2>/dev/null || printf '%s' "${USER:-unknown}")
  fi

  # Validate template
  case "$_template" in
    sh|python|go|web|generic) ;;
    *) die "Unknown template: $_template. Run 'mkproject list' to see available templates." ;;
  esac

  # Check directory doesn't exist
  [ ! -e "$_name" ] || die "Directory '$_name' already exists."

  # Create project directory
  mkdir -p "$_name"

  # Scaffold template
  case "$_template" in
    sh)      scaffold_sh "$_name" "$_name" ;;
    python)  scaffold_python "$_name" "$_name" ;;
    go)      scaffold_go "$_name" "$_name" ;;
    web)     scaffold_web "$_name" "$_name" ;;
    generic) scaffold_generic "$_name" ;;
  esac

  # License
  write_license "$_license" "$_author" "$_name/LICENSE"

  # README
  if [ "$_no_readme" -eq 0 ]; then
    write_readme "$_name" "$_name/README.md"
  fi

  # Git init
  if [ "$_no_git" -eq 0 ]; then
    if command -v git >/dev/null 2>&1; then
      git init "$_name" >/dev/null 2>&1
      success "Created project '$_name' (template: $_template) with git"
    else
      warn "git not found, skipping git init"
      success "Created project '$_name' (template: $_template)"
    fi
  else
    success "Created project '$_name' (template: $_template)"
  fi
}

# ── Main dispatch ──

if [ $# -lt 1 ]; then
  show_help
fi

cmd="$1"
shift

case "$cmd" in
  list)             cmd_list ;;
  help|-h|--help)   show_help ;;
  --version)        printf '%s\n' "$VERSION"; exit 0 ;;
  sh|python|go|web|generic)
    cmd_create "$cmd" "$@" ;;
  *)
    die "Unknown command: $cmd. Run 'mkproject help' for usage."
    ;;
esac
