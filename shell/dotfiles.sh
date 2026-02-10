#!/bin/sh

# Manage dotfiles with symlinks
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

confirm() {
  printf "%s [y/N]: " "$1"
  read -r answer
  case "$answer" in
    y|Y|yes|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Helpers ──

resolve_dotfiles_dir() {
  printf '%s' "${1:-$HOME/.dotfiles}"
}

expand_home() {
  # Expand $HOME in a target path
  eval printf '%s' "$1"
}

read_mapping() {
  _dotdir="$1"
  _mapping="$_dotdir/mapping.conf"
  [ -f "$_mapping" ] || return 0
  while IFS= read -r _line || [ -n "$_line" ]; do
    # Skip empty lines and comments
    case "$_line" in
      ""|\#*) continue ;;
    esac
    printf '%s\n' "$_line"
  done < "$_mapping"
}

mapping_source() {
  printf '%s' "$1" | cut -d: -f1
}

mapping_target() {
  printf '%s' "$1" | cut -d: -f2-
}

add_mapping_entry() {
  _dotdir="$1" _source="$2" _target="$3"
  _mapping="$_dotdir/mapping.conf"
  printf '%s:%s\n' "$_source" "$_target" >> "$_mapping"
}

remove_mapping_entry() {
  _dotdir="$1" _source="$2"
  _mapping="$_dotdir/mapping.conf"
  _tmpmap=$(mktemp)
  register_tmp "$_tmpmap"
  grep -v "^${_source}:" "$_mapping" > "$_tmpmap" || true
  mv "$_tmpmap" "$_mapping"
}

has_mapping_entry() {
  _dotdir="$1" _source="$2"
  _mapping="$_dotdir/mapping.conf"
  [ -f "$_mapping" ] && grep -q "^${_source}:" "$_mapping"
}

# ── Help ──

show_help() {
  prog=$(basename "$0")
  cat <<EOF
$prog – Manage dotfiles with symlinks

Usage:
  $prog <command> [options]

Commands:
  init               Initialize a dotfiles directory
  add <file>         Add a file to the dotfiles repo
  link [name]        Create symlinks from mapping
  unlink [name]      Remove symlinks (restore backups if available)
  status             Show status of all dotfiles
  diff [name]        Show differences between repo and active files
  list               List mapping entries
  remove <name>      Remove an entry from the mapping
  help, -h           Show this help message

Options:
  --dir <path>       Dotfiles directory (default: ~/.dotfiles)
  --force            Force overwrite / re-init
  --dry-run          Show what would be done without doing it
  --name <alias>     Custom name when adding a file
  --keep             Keep file in repo when removing from mapping

Examples:
  $prog init
  $prog add ~/.bashrc
  $prog add ~/.config/nvim --name nvim
  $prog link
  $prog link --dry-run
  $prog status
  $prog diff bashrc
  $prog unlink
  $prog remove bashrc
EOF
  exit 0
}

# ── Commands ──

cmd_init() {
  _dir="" _force=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --dir)   [ $# -ge 2 ] || die "--dir requires an argument"; _dir="$2"; shift 2 ;;
      --force) _force=1; shift ;;
      *)       die "Unknown option: $1" ;;
    esac
  done

  _dotdir=$(resolve_dotfiles_dir "$_dir")

  if [ -d "$_dotdir" ] && [ "$_force" -eq 0 ]; then
    die "Directory '$_dotdir' already exists. Use --force to re-initialize."
  fi

  mkdir -p "$_dotdir/.backup"
  if [ ! -f "$_dotdir/mapping.conf" ]; then
    printf '# source_in_dotfiles:target_path\n' > "$_dotdir/mapping.conf"
  fi

  success "Initialized dotfiles directory: $_dotdir"
}

cmd_add() {
  _dir="" _custom_name=""

  # Parse trailing options first, collect positional
  _file=""
  _args=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir)  [ $# -ge 2 ] || die "--dir requires an argument"; _dir="$2"; shift 2 ;;
      --name) [ $# -ge 2 ] || die "--name requires an argument"; _custom_name="$2"; shift 2 ;;
      -*)     die "Unknown option: $1" ;;
      *)
        if [ -z "$_file" ]; then
          _file="$1"
        else
          die "Unexpected argument: $1"
        fi
        shift
        ;;
    esac
  done

  [ -n "$_file" ] || die "Missing file argument. Usage: dotfiles add <file>"

  _dotdir=$(resolve_dotfiles_dir "$_dir")
  [ -d "$_dotdir" ] || die "Dotfiles directory not found: $_dotdir. Run 'dotfiles init' first."

  # Resolve absolute path of the file
  _abspath=$(cd "$(dirname "$_file")" && printf '%s/%s' "$(pwd)" "$(basename "$_file")")
  [ -e "$_abspath" ] || die "File not found: $_file"

  # Determine source name in repo
  if [ -n "$_custom_name" ]; then
    _source="$_custom_name"
  else
    # Strip leading $HOME/. from path
    _source=$(printf '%s' "$_abspath" | sed "s|^$HOME/\.||; s|^$HOME/||")
  fi

  # Check not already tracked
  if has_mapping_entry "$_dotdir" "$_source"; then
    die "'$_source' is already tracked in mapping.conf"
  fi

  # Move to dotfiles dir
  _dest="$_dotdir/$_source"
  mkdir -p "$(dirname "$_dest")"
  if [ -d "$_abspath" ]; then
    cp -a "$_abspath" "$_dest"
    rm -rf "$_abspath"
  else
    mv "$_abspath" "$_dest"
  fi

  # Create symlink
  ln -s "$_dest" "$_abspath"

  # Add to mapping
  add_mapping_entry "$_dotdir" "$_source" "$_abspath"

  success "Added '$_source' → $_abspath"
}

cmd_link() {
  _dir="" _dry_run=0 _force=0 _single=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --dir)     [ $# -ge 2 ] || die "--dir requires an argument"; _dir="$2"; shift 2 ;;
      --dry-run) _dry_run=1; shift ;;
      --force)   _force=1; shift ;;
      -*)        die "Unknown option: $1" ;;
      *)         _single="$1"; shift ;;
    esac
  done

  _dotdir=$(resolve_dotfiles_dir "$_dir")
  [ -d "$_dotdir" ] || die "Dotfiles directory not found: $_dotdir"

  _count=0
  read_mapping "$_dotdir" | while IFS= read -r _entry; do
    _source=$(mapping_source "$_entry")
    _target=$(expand_home "$(mapping_target "$_entry")")

    # If linking a single file, skip others
    if [ -n "$_single" ] && [ "$_source" != "$_single" ]; then
      continue
    fi

    _src_path="$_dotdir/$_source"
    [ -e "$_src_path" ] || { warn "Source not found: $_source"; continue; }

    if [ "$_dry_run" -eq 1 ]; then
      printf "Would link: %s → %s\n" "$_source" "$_target"
      continue
    fi

    # Handle existing target
    if [ -e "$_target" ] || [ -L "$_target" ]; then
      if [ -L "$_target" ]; then
        rm -f "$_target"
      elif [ "$_force" -eq 1 ]; then
        # Backup before overwriting
        _backup_dest="$_dotdir/.backup/$(basename "$_target")"
        mkdir -p "$_dotdir/.backup"
        if [ -d "$_target" ]; then
          cp -a "$_target" "$_backup_dest"
          rm -rf "$_target"
        else
          mv "$_target" "$_backup_dest"
        fi
      else
        warn "Target exists: $_target (use --force to overwrite)"
        continue
      fi
    fi

    mkdir -p "$(dirname "$_target")"
    ln -s "$_src_path" "$_target"
    success "Linked: $_source → $_target"
  done
}

cmd_unlink() {
  _dir="" _dry_run=0 _single=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --dir)     [ $# -ge 2 ] || die "--dir requires an argument"; _dir="$2"; shift 2 ;;
      --dry-run) _dry_run=1; shift ;;
      -*)        die "Unknown option: $1" ;;
      *)         _single="$1"; shift ;;
    esac
  done

  _dotdir=$(resolve_dotfiles_dir "$_dir")
  [ -d "$_dotdir" ] || die "Dotfiles directory not found: $_dotdir"

  read_mapping "$_dotdir" | while IFS= read -r _entry; do
    _source=$(mapping_source "$_entry")
    _target=$(expand_home "$(mapping_target "$_entry")")

    if [ -n "$_single" ] && [ "$_source" != "$_single" ]; then
      continue
    fi

    if [ -L "$_target" ]; then
      if [ "$_dry_run" -eq 1 ]; then
        printf "Would unlink: %s\n" "$_target"
      else
        rm -f "$_target"
        # Restore backup if available
        _backup="$_dotdir/.backup/$(basename "$_target")"
        if [ -e "$_backup" ]; then
          if [ -d "$_backup" ]; then
            cp -a "$_backup" "$_target"
          else
            mv "$_backup" "$_target"
          fi
          success "Unlinked and restored: $_target"
        else
          success "Unlinked: $_target"
        fi
      fi
    fi
  done
}

cmd_status() {
  _dir=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --dir) [ $# -ge 2 ] || die "--dir requires an argument"; _dir="$2"; shift 2 ;;
      *)     die "Unknown option: $1" ;;
    esac
  done

  _dotdir=$(resolve_dotfiles_dir "$_dir")
  [ -d "$_dotdir" ] || die "Dotfiles directory not found: $_dotdir"

  printf "Dotfiles status (%s):\n" "$_dotdir"

  read_mapping "$_dotdir" | while IFS= read -r _entry; do
    _source=$(mapping_source "$_entry")
    _target=$(expand_home "$(mapping_target "$_entry")")

    if [ -L "$_target" ]; then
      _link_dest=$(readlink "$_target" 2>/dev/null || true)
      if [ "$_link_dest" = "$_dotdir/$_source" ]; then
        printf "  linked     %-20s → %s\n" "$_source" "$_target"
      else
        printf "  wrong link %-20s → %s (points to %s)\n" "$_source" "$_target" "$_link_dest"
      fi
    elif [ -e "$_target" ]; then
      printf "  conflict   %-20s → %s (regular file)\n" "$_source" "$_target"
    else
      printf "  not linked %-20s → %s\n" "$_source" "$_target"
    fi
  done
}

cmd_diff() {
  _dir="" _single=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --dir) [ $# -ge 2 ] || die "--dir requires an argument"; _dir="$2"; shift 2 ;;
      -*)    die "Unknown option: $1" ;;
      *)     _single="$1"; shift ;;
    esac
  done

  _dotdir=$(resolve_dotfiles_dir "$_dir")
  [ -d "$_dotdir" ] || die "Dotfiles directory not found: $_dotdir"

  read_mapping "$_dotdir" | while IFS= read -r _entry; do
    _source=$(mapping_source "$_entry")
    _target=$(expand_home "$(mapping_target "$_entry")")

    if [ -n "$_single" ] && [ "$_source" != "$_single" ]; then
      continue
    fi

    _src_path="$_dotdir/$_source"
    if [ -e "$_src_path" ] && [ -e "$_target" ] && [ ! -L "$_target" ]; then
      printf "=== %s ===\n" "$_source"
      diff "$_src_path" "$_target" || true
    fi
  done
}

cmd_list() {
  _dir=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --dir) [ $# -ge 2 ] || die "--dir requires an argument"; _dir="$2"; shift 2 ;;
      *)     die "Unknown option: $1" ;;
    esac
  done

  _dotdir=$(resolve_dotfiles_dir "$_dir")
  [ -d "$_dotdir" ] || die "Dotfiles directory not found: $_dotdir"

  read_mapping "$_dotdir" | while IFS= read -r _entry; do
    _source=$(mapping_source "$_entry")
    _target=$(mapping_target "$_entry")
    printf "%-30s → %s\n" "$_source" "$_target"
  done
}

cmd_remove() {
  _dir="" _keep=0 _name=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --dir)  [ $# -ge 2 ] || die "--dir requires an argument"; _dir="$2"; shift 2 ;;
      --keep) _keep=1; shift ;;
      -*)     die "Unknown option: $1" ;;
      *)
        [ -z "$_name" ] || die "Unexpected argument: $1"
        _name="$1"; shift
        ;;
    esac
  done

  [ -n "$_name" ] || die "Missing name argument. Usage: dotfiles remove <name>"

  _dotdir=$(resolve_dotfiles_dir "$_dir")
  [ -d "$_dotdir" ] || die "Dotfiles directory not found: $_dotdir"

  has_mapping_entry "$_dotdir" "$_name" || die "'$_name' not found in mapping.conf"

  # Find the target from mapping
  _target=""
  read_mapping "$_dotdir" | while IFS= read -r _entry; do
    _s=$(mapping_source "$_entry")
    if [ "$_s" = "$_name" ]; then
      _t=$(expand_home "$(mapping_target "$_entry")")
      # Unlink if symlink
      if [ -L "$_t" ]; then
        rm -f "$_t"
        # Restore backup if available
        _backup="$_dotdir/.backup/$(basename "$_t")"
        if [ -e "$_backup" ]; then
          if [ -d "$_backup" ]; then
            cp -a "$_backup" "$_t"
          else
            mv "$_backup" "$_t"
          fi
        fi
      fi
      break
    fi
  done

  # Remove from mapping
  remove_mapping_entry "$_dotdir" "$_name"

  # Remove from repo (unless --keep)
  if [ "$_keep" -eq 0 ] && [ -e "$_dotdir/$_name" ]; then
    rm -rf "$_dotdir/$_name"
  fi

  success "Removed '$_name' from dotfiles"
}

# ── Main dispatch ──

if [ $# -lt 1 ]; then
  show_help
fi

cmd="$1"
shift

case "$cmd" in
  init)             cmd_init "$@" ;;
  add)              cmd_add "$@" ;;
  link)             cmd_link "$@" ;;
  unlink)           cmd_unlink "$@" ;;
  status)           cmd_status "$@" ;;
  diff)             cmd_diff "$@" ;;
  list)             cmd_list "$@" ;;
  remove)           cmd_remove "$@" ;;
  help|-h|--help)   show_help ;;
  --version)        printf '%s\n' "$VERSION"; exit 0 ;;
  *)
    die "Unknown command: $cmd. Run 'dotfiles help' for usage."
    ;;
esac
