#!/bin/sh

# Installer for mhbxyz/scripts — shell utilities
# Usage: curl -fsSL https://raw.githubusercontent.com/mhbxyz/scripts/main/install.sh | sh

set -eu

# ── Constants ──

RESET="\033[0m"
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"

SCRIPTS_BASE_URL="${SCRIPTS_REPO_URL:-https://raw.githubusercontent.com/mhbxyz/scripts/main}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

MANIFEST="gpgkeys|gpgkeys.sh|Generate and manage GPG keys
sshkeys|sshkeys.sh|Generate and manage SSH keys
homebackup|homebackup.sh|Backup home directory to external drive
fix-pacman-gpg|fix-pacman-gpg.sh|Fix pacman GPG errors on Arch/Manjaro
enable-emoji-support-for-arch|enable-emoji-support-for-arch.sh|Enable emoji support on Arch
uninstall-jetbrains-toolbox|uninstall-jetbrains-toolbox.sh|Uninstall JetBrains Toolbox"

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
  printf "${RED}Error: %s${RESET}\n" "$*" >&2
  exit 1
}

warn() {
  printf "${YELLOW}Warning: %s${RESET}\n" "$*" >&2
}

info() {
  printf "${BLUE}%s${RESET}\n" "$*"
}

success() {
  printf "${GREEN}%s${RESET}\n" "$*"
}

# ── Helpers ──

download_file() {
  _url="$1" _dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$_url" -o "$_dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$_dest" "$_url"
  else
    die "Neither curl nor wget found. Please install one of them."
  fi
}

manifest_count() {
  printf '%s\n' "$MANIFEST" | wc -l
}

manifest_entry() {
  printf '%s\n' "$MANIFEST" | awk "NR==$1"
}

manifest_name() {
  printf '%s' "$1" | cut -d'|' -f1
}

manifest_filename() {
  printf '%s' "$1" | cut -d'|' -f2
}

manifest_desc() {
  printf '%s' "$1" | cut -d'|' -f3
}

validate_script_name() {
  _vname="$1"
  _found=0
  _i=1
  _total=$(manifest_count)
  while [ "$_i" -le "$_total" ]; do
    _entry=$(manifest_entry "$_i")
    if [ "$(manifest_name "$_entry")" = "$_vname" ]; then
      _found=1
      break
    fi
    _i=$((_i + 1))
  done
  if [ "$_found" -eq 0 ]; then
    die "Unknown script: '$_vname'. Run '$0 help' to see available scripts."
  fi
}

get_filename_for() {
  _gname="$1"
  _i=1
  _total=$(manifest_count)
  while [ "$_i" -le "$_total" ]; do
    _entry=$(manifest_entry "$_i")
    if [ "$(manifest_name "$_entry")" = "$_gname" ]; then
      manifest_filename "$_entry"
      return
    fi
    _i=$((_i + 1))
  done
}

get_installed_scripts() {
  _installed=""
  _i=1
  _total=$(manifest_count)
  while [ "$_i" -le "$_total" ]; do
    _entry=$(manifest_entry "$_i")
    _name=$(manifest_name "$_entry")
    if [ -f "$INSTALL_DIR/$_name" ]; then
      _installed="$_installed $_name"
    fi
    _i=$((_i + 1))
  done
  printf '%s' "$_installed" | sed 's/^ //'
}

get_all_names() {
  _names=""
  _i=1
  _total=$(manifest_count)
  while [ "$_i" -le "$_total" ]; do
    _entry=$(manifest_entry "$_i")
    _names="$_names $(manifest_name "$_entry")"
    _i=$((_i + 1))
  done
  printf '%s' "$_names" | sed 's/^ //'
}

install_script() {
  _name="$1" _filename="$2"
  _url="$SCRIPTS_BASE_URL/shell/$_filename"
  _tmpfile=$(mktemp)
  register_tmp "$_tmpfile"
  if ! download_file "$_url" "$_tmpfile"; then
    die "Failed to download '$_name' from $_url"
  fi
  mv "$_tmpfile" "$INSTALL_DIR/$_name"
  chmod +x "$INSTALL_DIR/$_name"
  success "Installed: $_name"
}

check_path() {
  case ":${PATH}:" in
    *":${INSTALL_DIR}:"*) ;;
    *)
      warn "$INSTALL_DIR is not in your PATH."
      warn "Add it with: export PATH=\"$INSTALL_DIR:\$PATH\""
      ;;
  esac
}

show_menu() {
  info "Available scripts:"
  printf "\n"
  _i=1
  _total=$(manifest_count)
  while [ "$_i" -le "$_total" ]; do
    _entry=$(manifest_entry "$_i")
    _name=$(manifest_name "$_entry")
    _desc=$(manifest_desc "$_entry")
    printf "  %d) %-35s %s\n" "$_i" "$_name" "$_desc"
    _i=$((_i + 1))
  done
  printf "  a) All scripts\n"
  printf "\nSelect scripts to install (e.g. 1 3 5 or a): "
  read -r _choice </dev/tty

  if [ "$_choice" = "a" ] || [ "$_choice" = "A" ]; then
    get_all_names
    return
  fi

  _selected=""
  for _num in $_choice; do
    case "$_num" in
      *[!0-9]*) die "Invalid selection: '$_num'" ;;
    esac
    if [ "$_num" -lt 1 ] || [ "$_num" -gt "$_total" ]; then
      die "Selection out of range: $_num (1-$_total)"
    fi
    _entry=$(manifest_entry "$_num")
    _selected="$_selected $(manifest_name "$_entry")"
  done
  printf '%s' "$_selected" | sed 's/^ //'
}

# ── Help ──

show_help() {
  cat <<'EOF'
Usage: install.sh [command] [options]

Commands:
  install     Install scripts (default)
  uninstall   Remove installed scripts
  update      Update installed scripts
  help        Show this help message

Options:
  --all           Select all scripts (skip interactive menu)
  --only "A B"    Install/uninstall specific scripts by name
  --dir DIR       Set install directory (default: ~/.local/bin)
  -h, --help      Show this help message

Available scripts:
  gpgkeys                        Generate and manage GPG keys
  sshkeys                        Generate and manage SSH keys
  homebackup                     Backup home directory to external drive
  fix-pacman-gpg                 Fix pacman GPG errors on Arch/Manjaro
  enable-emoji-support-for-arch  Enable emoji support on Arch
  uninstall-jetbrains-toolbox    Uninstall JetBrains Toolbox

Examples:
  curl -fsSL https://raw.githubusercontent.com/mhbxyz/scripts/main/install.sh | sh
  curl -fsSL .../install.sh | sh -s -- --all
  curl -fsSL .../install.sh | sh -s -- --only "gpgkeys sshkeys"
  curl -fsSL .../install.sh | sh -s -- uninstall --all
  curl -fsSL .../install.sh | sh -s -- update
EOF
}

# ── Commands ──

cmd_install() {
  _mode="" _only_scripts="" _dir=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --all)  _mode="all"; shift ;;
      --only)
        [ $# -ge 2 ] || die "--only requires an argument"
        _mode="only"; _only_scripts="$2"; shift 2 ;;
      --dir)
        [ $# -ge 2 ] || die "--dir requires an argument"
        _dir="$2"; shift 2 ;;
      *)  die "Unknown option: '$1'" ;;
    esac
  done

  [ -n "$_dir" ] && INSTALL_DIR="$_dir"
  mkdir -p "$INSTALL_DIR"

  case "$_mode" in
    all)
      _scripts=$(get_all_names)
      ;;
    only)
      [ -n "$_only_scripts" ] || die "--only requires at least one script name"
      for _s in $_only_scripts; do
        validate_script_name "$_s"
      done
      _scripts="$_only_scripts"
      ;;
    *)
      _scripts=$(show_menu)
      [ -n "$_scripts" ] || die "No scripts selected"
      ;;
  esac

  _count=0
  for _name in $_scripts; do
    _filename=$(get_filename_for "$_name")
    install_script "$_name" "$_filename"
    _count=$((_count + 1))
  done

  printf "\n"
  success "Installed $_count script(s) to $INSTALL_DIR"
  check_path
}

cmd_uninstall() {
  _mode="all" _only_scripts="" _dir=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --all)  _mode="all"; shift ;;
      --only)
        [ $# -ge 2 ] || die "--only requires an argument"
        _mode="only"; _only_scripts="$2"; shift 2 ;;
      --dir)
        [ $# -ge 2 ] || die "--dir requires an argument"
        _dir="$2"; shift 2 ;;
      *)  die "Unknown option: '$1'" ;;
    esac
  done

  [ -n "$_dir" ] && INSTALL_DIR="$_dir"

  case "$_mode" in
    all)
      _scripts=$(get_all_names)
      ;;
    only)
      [ -n "$_only_scripts" ] || die "--only requires at least one script name"
      for _s in $_only_scripts; do
        validate_script_name "$_s"
      done
      _scripts="$_only_scripts"
      ;;
  esac

  _count=0
  for _name in $_scripts; do
    if [ -f "$INSTALL_DIR/$_name" ]; then
      rm -f "$INSTALL_DIR/$_name"
      success "Removed: $_name"
      _count=$((_count + 1))
    fi
  done

  if [ "$_count" -eq 0 ]; then
    info "No scripts to remove."
  else
    printf "\n"
    success "Removed $_count script(s) from $INSTALL_DIR"
  fi
}

cmd_update() {
  _dir=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --dir)
        [ $# -ge 2 ] || die "--dir requires an argument"
        _dir="$2"; shift 2 ;;
      *)  die "Unknown option: '$1'" ;;
    esac
  done

  [ -n "$_dir" ] && INSTALL_DIR="$_dir"

  _installed=$(get_installed_scripts)
  if [ -z "$_installed" ]; then
    info "No scripts currently installed in $INSTALL_DIR."
    return 0
  fi

  _count=0
  for _name in $_installed; do
    _filename=$(get_filename_for "$_name")
    install_script "$_name" "$_filename"
    _count=$((_count + 1))
  done

  printf "\n"
  success "Updated $_count script(s) in $INSTALL_DIR"
}

# ── Main dispatch ──

cmd=""
if [ $# -gt 0 ]; then
  case "$1" in
    install)   cmd="install";   shift ;;
    uninstall) cmd="uninstall"; shift ;;
    update)    cmd="update";    shift ;;
    help|-h|--help) show_help; exit 0 ;;
    --*)       cmd="install" ;;  # flags without subcommand → install
    *)         die "Unknown command: '$1'. Run '$0 help' for usage." ;;
  esac
else
  cmd="install"
fi

case "$cmd" in
  install)   cmd_install "$@" ;;
  uninstall) cmd_uninstall "$@" ;;
  update)    cmd_update "$@" ;;
esac
