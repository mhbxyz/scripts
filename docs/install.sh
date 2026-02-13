#!/bin/sh

# Installer for mhbxyz/scripts — shell utilities
# Usage: curl -fsSL https://mhbxyz.github.io/scripts/install.sh | sh

set -eu

# ── Constants ──

RESET="\033[0m"
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"

SCRIPTS_BASE_URL="${SCRIPTS_REPO_URL:-https://raw.githubusercontent.com/mhbxyz/scripts/main}"
RELEASES_BASE_URL="${RELEASES_BASE_URL:-https://github.com/mhbxyz/scripts/releases/download}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

MANIFEST="gpgkeys|gpgkeys.sh|Generate and manage GPG keys|shell
sshkeys|sshkeys.sh|Generate and manage SSH keys|shell
homebackup|homebackup.sh|Backup home directory to external drive|shell
sortdownloads|sortdownloads.sh|Sort Downloads folder into organized subdirectories|shell
mygit|mygit.sh|Simplified git config management|shell
dotfiles|dotfiles.sh|Manage dotfiles with symlinks|shell
mkproject|mkproject.sh|Scaffold new projects from templates|shell
cleanup|cleanup.sh|Free disk space by cleaning caches and temp files|shell
imgstotxt|imgstotxt|OCR images to text file|binary|imgstotxt-latest
pdftoimgs|pdftoimgs|Convert PDF to images|binary|pdftoimgs-latest
keepalive|keepalive|Simulate activity to prevent idle status|binary|keepalive-latest"

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

manifest_type() {
  _type=$(printf '%s' "$1" | cut -d'|' -f4)
  printf '%s' "${_type:-shell}"
}

manifest_release_tag() {
  printf '%s' "$1" | cut -d'|' -f5
}

get_type_for() {
  _gname="$1"
  _i=1
  _total=$(manifest_count)
  while [ "$_i" -le "$_total" ]; do
    _entry=$(manifest_entry "$_i")
    if [ "$(manifest_name "$_entry")" = "$_gname" ]; then
      manifest_type "$_entry"
      return
    fi
    _i=$((_i + 1))
  done
}

get_release_tag_for() {
  _gname="$1"
  _i=1
  _total=$(manifest_count)
  while [ "$_i" -le "$_total" ]; do
    _entry=$(manifest_entry "$_i")
    if [ "$(manifest_name "$_entry")" = "$_gname" ]; then
      manifest_release_tag "$_entry"
      return
    fi
    _i=$((_i + 1))
  done
}

detect_platform() {
  _os=$(uname -s | tr '[:upper:]' '[:lower:]')
  _arch=$(uname -m)
  printf '%s %s' "$_os" "$_arch"
}

# ── Metadata helpers ──

compute_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

read_meta_version() {
  _meta="$INSTALL_DIR/.scripts-meta"
  [ -f "$_meta" ] || return 0
  grep "^$1|" "$_meta" | cut -d'|' -f2
}

read_meta_checksum() {
  _meta="$INSTALL_DIR/.scripts-meta"
  [ -f "$_meta" ] || return 0
  grep "^$1|" "$_meta" | cut -d'|' -f3
}

write_meta() {
  _meta="$INSTALL_DIR/.scripts-meta"
  if [ -f "$_meta" ]; then
    grep -v "^$1|" "$_meta" > "$_meta.tmp" || true
    mv "$_meta.tmp" "$_meta"
  fi
  printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$_meta"
}

remove_meta() {
  _meta="$INSTALL_DIR/.scripts-meta"
  [ -f "$_meta" ] || return 0
  grep -v "^$1|" "$_meta" > "$_meta.tmp" || true
  mv "$_meta.tmp" "$_meta"
}

extract_shell_version() {
  grep '^VERSION=' "$1" 2>/dev/null | head -1 | cut -d'"' -f2
}

check_binary_deps() {
  _name="$1"
  case "$_name" in
    imgstotxt)
      if ! command -v tesseract >/dev/null 2>&1; then
        warn "tesseract is not installed. imgstotxt requires tesseract-ocr to function."
      fi
      ;;
  esac
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
  _name="$1" _filename="$2" _type="${3:-shell}"
  _tmpfile=$(mktemp)
  register_tmp "$_tmpfile"

  case "$_type" in
    shell)
      _url="$SCRIPTS_BASE_URL/shell/$_filename"
      ;;
    binary)
      _release_tag=$(get_release_tag_for "$_name")
      _platform=$(detect_platform)
      _pos=$(printf '%s' "$_platform" | cut -d' ' -f1)
      _parch=$(printf '%s' "$_platform" | cut -d' ' -f2)
      _url="$RELEASES_BASE_URL/$_release_tag/$_filename-$_pos-$_parch"
      check_binary_deps "$_name"
      ;;
    *)
      die "Unknown type '$_type' for script '$_name'"
      ;;
  esac

  if ! download_file "$_url" "$_tmpfile"; then
    die "Failed to download '$_name' from $_url"
  fi
  mv "$_tmpfile" "$INSTALL_DIR/$_name"
  chmod +x "$INSTALL_DIR/$_name"

  _sha256=$(compute_sha256 "$INSTALL_DIR/$_name")
  case "$_type" in
    shell)  _ver=$(extract_shell_version "$INSTALL_DIR/$_name") ;;
    binary) _ver=$("$INSTALL_DIR/$_name" --version 2>/dev/null | awk '{print $NF}') ;;
  esac
  write_meta "$_name" "${_ver:-unknown}" "$_sha256"

  success "Installed: $_name (${_ver:-unknown})"
}

update_script() {
  _name="$1" _filename="$2" _type="${3:-shell}"
  _old_sha=$(read_meta_checksum "$_name")
  _old_ver=$(read_meta_version "$_name")

  case "$_type" in
    shell)
      _tmpfile=$(mktemp)
      register_tmp "$_tmpfile"
      _url="$SCRIPTS_BASE_URL/shell/$_filename"
      if ! download_file "$_url" "$_tmpfile"; then
        die "Failed to download '$_name' from $_url"
      fi
      _new_sha=$(compute_sha256 "$_tmpfile")
      if [ -n "$_old_sha" ] && [ "$_new_sha" = "$_old_sha" ]; then
        info "$_name: up to date ($_old_ver)"
        rm -f "$_tmpfile"
        return 1
      fi
      _new_ver=$(extract_shell_version "$_tmpfile")
      mv "$_tmpfile" "$INSTALL_DIR/$_name"
      chmod +x "$INSTALL_DIR/$_name"
      write_meta "$_name" "${_new_ver:-unknown}" "$_new_sha"
      ;;
    binary)
      _release_tag=$(get_release_tag_for "$_name")
      _platform=$(detect_platform)
      _pos=$(printf '%s' "$_platform" | cut -d' ' -f1)
      _parch=$(printf '%s' "$_platform" | cut -d' ' -f2)
      _base="$_filename-$_pos-$_parch"
      _sha_url="$RELEASES_BASE_URL/$_release_tag/$_base.sha256"
      _tmpsha=$(mktemp)
      register_tmp "$_tmpsha"
      if download_file "$_sha_url" "$_tmpsha" 2>/dev/null; then
        _new_sha=$(cat "$_tmpsha")
        if [ -n "$_old_sha" ] && [ "$_new_sha" = "$_old_sha" ]; then
          info "$_name: up to date ($_old_ver)"
          return 1
        fi
      fi
      _tmpfile=$(mktemp)
      register_tmp "$_tmpfile"
      _url="$RELEASES_BASE_URL/$_release_tag/$_base"
      check_binary_deps "$_name"
      if ! download_file "$_url" "$_tmpfile"; then
        die "Failed to download '$_name' from $_url"
      fi
      _new_sha=$(compute_sha256 "$_tmpfile")
      mv "$_tmpfile" "$INSTALL_DIR/$_name"
      chmod +x "$INSTALL_DIR/$_name"
      _new_ver=$("$INSTALL_DIR/$_name" --version 2>/dev/null | awk '{print $NF}')
      write_meta "$_name" "${_new_ver:-unknown}" "$_new_sha"
      ;;
  esac

  if [ -n "$_old_ver" ] && [ "$_old_ver" != "unknown" ]; then
    success "Updated: $_name ($_old_ver → ${_new_ver:-unknown})"
  else
    success "Updated: $_name"
  fi
  return 0
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
  info "Available scripts:" >/dev/tty
  printf "\n" >/dev/tty
  _i=1
  _total=$(manifest_count)
  while [ "$_i" -le "$_total" ]; do
    _entry=$(manifest_entry "$_i")
    _name=$(manifest_name "$_entry")
    _desc=$(manifest_desc "$_entry")
    _ver=$(read_meta_version "$_name")
    if [ -n "$_ver" ]; then
      _label="$_name ($_ver)"
    else
      _label="$_name"
    fi
    printf "  %d) %-35s %s\n" "$_i" "$_label" "$_desc" >/dev/tty
    _i=$((_i + 1))
  done
  printf "  a) All scripts\n" >/dev/tty
  printf "\nSelect scripts to install (e.g. 1 3 5 or a): " >/dev/tty
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
  sortdownloads                  Sort Downloads folder into organized subdirectories
  mygit                          Simplified git config management
  dotfiles                       Manage dotfiles with symlinks
  mkproject                      Scaffold new projects from templates
  cleanup                        Free disk space by cleaning caches and temp files
  imgstotxt                      OCR images to text file
  pdftoimgs                      Convert PDF to images
  keepalive                      Simulate activity to prevent idle status

Examples:
  curl -fsSL https://mhbxyz.github.io/scripts/install.sh | sh
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
    _type=$(get_type_for "$_name")
    install_script "$_name" "$_filename" "$_type"
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
      remove_meta "$_name"
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
  _skipped=0
  for _name in $_installed; do
    _filename=$(get_filename_for "$_name")
    _type=$(get_type_for "$_name")
    if update_script "$_name" "$_filename" "$_type"; then
      _count=$((_count + 1))
    else
      _skipped=$((_skipped + 1))
    fi
  done

  printf "\n"
  if [ "$_count" -gt 0 ]; then
    success "Updated $_count script(s) in $INSTALL_DIR"
  fi
  if [ "$_skipped" -gt 0 ]; then
    info "$_skipped script(s) already up to date"
  fi
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
