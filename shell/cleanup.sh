#!/bin/sh

# Free disk space by cleaning caches and temp files
# Author: Manoah Bernier

set -eu

VERSION="1.0.1"

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
  read -r answer </dev/tty 2>/dev/null || answer=""
  case "$answer" in
    y|Y|yes|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Size helpers ──

human_size() {
  _bytes="$1"
  if [ "$_bytes" -ge 1073741824 ]; then
    _gb=$((_bytes / 1073741824))
    _mb=$(( (_bytes % 1073741824) / 10737418 ))
    printf '%d.%d GB' "$_gb" "$_mb"
  elif [ "$_bytes" -ge 1048576 ]; then
    _mb=$((_bytes / 1048576))
    printf '%d MB' "$_mb"
  elif [ "$_bytes" -ge 1024 ]; then
    _kb=$((_bytes / 1024))
    printf '%d KB' "$_kb"
  else
    printf '%d B' "$_bytes"
  fi
}

dir_size_bytes() {
  if [ -d "$1" ]; then
    du -sb "$1" 2>/dev/null | cut -f1 || printf '0'
  else
    printf '0'
  fi
}

# ── Platform detection ──

detect_package_manager() {
  if command -v paccache >/dev/null 2>&1; then
    printf 'pacman'
  elif command -v apt >/dev/null 2>&1; then
    printf 'apt'
  elif command -v brew >/dev/null 2>&1; then
    printf 'brew'
  else
    printf 'none'
  fi
}

# ── Targets ──

# Each target has: scan_<target> (prints size in bytes) and clean_<target>

scan_packages() {
  _pm=$(detect_package_manager)
  case "$_pm" in
    pacman)
      _cache="/var/cache/pacman/pkg"
      [ -d "$_cache" ] && dir_size_bytes "$_cache" || printf '0'
      ;;
    apt)
      _cache="/var/cache/apt/archives"
      [ -d "$_cache" ] && dir_size_bytes "$_cache" || printf '0'
      ;;
    brew)
      _size=0
      if command -v brew >/dev/null 2>&1; then
        _cache="$(brew --cache 2>/dev/null || true)"
        [ -d "$_cache" ] && _size=$(dir_size_bytes "$_cache")
      fi
      printf '%s' "$_size"
      ;;
    *) printf '0' ;;
  esac
}

clean_packages() {
  _pm=$(detect_package_manager)
  case "$_pm" in
    pacman) sudo paccache -rk1 ;;
    apt)    sudo apt clean ;;
    brew)   brew cleanup ;;
    *)      warn "No supported package manager found" ;;
  esac
}

packages_needs_sudo() {
  _pm=$(detect_package_manager)
  case "$_pm" in
    pacman|apt) return 0 ;;
    *)          return 1 ;;
  esac
}

scan_trash() {
  _trash="$HOME/.local/share/Trash"
  [ -d "$_trash" ] && dir_size_bytes "$_trash" || printf '0'
}

clean_trash() {
  _trash="$HOME/.local/share/Trash"
  if [ -d "$_trash" ]; then
    rm -rf "${_trash:?}/"*
    success "Cleaned trash"
  fi
}

scan_journal() {
  if command -v journalctl >/dev/null 2>&1; then
    journalctl --disk-usage 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)?[KMGT]' | head -1 | {
      read -r _val || true
      case "$_val" in
        *G) _num="${_val%G}"; printf '%s' "$(( ${_num%.*} * 1073741824 ))" ;;
        *M) _num="${_val%M}"; printf '%s' "$(( ${_num%.*} * 1048576 ))" ;;
        *K) _num="${_val%K}"; printf '%s' "$(( ${_num%.*} * 1024 ))" ;;
        *)  printf '0' ;;
      esac
    }
  else
    printf '0'
  fi
}

clean_journal() {
  if command -v journalctl >/dev/null 2>&1; then
    sudo journalctl --vacuum-time=7d
    success "Cleaned journal logs"
  fi
}

scan_docker() {
  if command -v docker >/dev/null 2>&1; then
    _output=$(docker system df 2>/dev/null | tail -n +2 || true)
    if [ -n "$_output" ]; then
      _total=0
      while IFS= read -r _line; do
        _reclaim=$(printf '%s' "$_line" | awk '{print $NF}')
        case "$_reclaim" in
          *GB) _num="${_reclaim%GB}"; _total=$((_total + ${_num%.*} * 1073741824)) ;;
          *MB) _num="${_reclaim%MB}"; _total=$((_total + ${_num%.*} * 1048576)) ;;
          *kB) _num="${_reclaim%kB}"; _total=$((_total + ${_num%.*} * 1024)) ;;
          *B)  _num="${_reclaim%B}";  _total=$((_total + ${_num%.*})) ;;
        esac
      done <<EOF_DOCKER
$_output
EOF_DOCKER
      printf '%s' "$_total"
    else
      printf '0'
    fi
  else
    printf '0'
  fi
}

clean_docker() {
  if command -v docker >/dev/null 2>&1; then
    docker system prune -f
    success "Cleaned Docker"
  fi
}

scan_thumbnails() {
  _thumbs="$HOME/.cache/thumbnails"
  [ -d "$_thumbs" ] && dir_size_bytes "$_thumbs" || printf '0'
}

clean_thumbnails() {
  _thumbs="$HOME/.cache/thumbnails"
  if [ -d "$_thumbs" ]; then
    rm -rf "$_thumbs"
    success "Cleaned thumbnails"
  fi
}

scan_downloads() {
  _dl="$HOME/Downloads"
  _size=0
  if [ -d "$_dl" ]; then
    for _f in "$_dl"/*.part "$_dl"/*.crdownload; do
      [ -f "$_f" ] || continue
      _fsize=$(du -sb "$_f" 2>/dev/null | cut -f1 || true)
      _size=$((_size + ${_fsize:-0}))
    done
  fi
  printf '%s' "$_size"
}

clean_downloads() {
  _dl="$HOME/Downloads"
  if [ -d "$_dl" ]; then
    _count=0
    for _f in "$_dl"/*.part "$_dl"/*.crdownload; do
      [ -f "$_f" ] || continue
      rm -f "$_f"
      _count=$((_count + 1))
    done
    success "Cleaned $_count partial download(s)"
  fi
}

scan_cache() {
  _threshold="${1:-104857600}"  # 100MB default
  _cachedir="$HOME/.cache"
  _total=0
  if [ -d "$_cachedir" ]; then
    for _d in "$_cachedir"/*/; do
      [ -d "$_d" ] || continue
      _basename=$(basename "$_d")
      # Skip thumbnails (handled separately)
      [ "$_basename" = "thumbnails" ] && continue
      _dsize=$(dir_size_bytes "$_d")
      if [ "$_dsize" -ge "$_threshold" ]; then
        _total=$((_total + _dsize))
      fi
    done
  fi
  printf '%s' "$_total"
}

clean_cache() {
  _threshold="${1:-104857600}"
  _cachedir="$HOME/.cache"
  if [ -d "$_cachedir" ]; then
    for _d in "$_cachedir"/*/; do
      [ -d "$_d" ] || continue
      _basename=$(basename "$_d")
      [ "$_basename" = "thumbnails" ] && continue
      _dsize=$(dir_size_bytes "$_d")
      if [ "$_dsize" -ge "$_threshold" ]; then
        rm -rf "$_d"
        info "Removed cache: $_basename ($(human_size "$_dsize"))"
      fi
    done
    success "Cleaned large caches"
  fi
}

# ── Help ──

show_help() {
  prog=$(basename "$0")
  cat <<EOF
$prog – Free disk space by cleaning caches and temp files

Usage:
  $prog [command] [options]

Commands:
  scan             Dry-run: show reclaimable space (default)
  run              Execute cleanup
  help, -h         Show this help message

Options:
  --no-confirm             Skip confirmation prompts (for run)
  --target <name>          Clean specific target only
  --cache-threshold <MB>   Threshold for user caches in MB (default: 100)
  --no-sudo                Skip operations requiring sudo

Targets:
  packages       Package manager cache (pacman/apt/brew)
  trash          User trash (~/.local/share/Trash)
  journal        Systemd journal logs
  docker         Docker unused data
  thumbnails     Thumbnail cache
  downloads      Partial downloads
  cache          User caches above threshold

Examples:
  $prog
  $prog scan
  $prog run --no-confirm
  $prog run --target trash
  $prog run --target cache --cache-threshold 50
  $prog run --no-sudo
EOF
  exit 0
}

# ── Commands ──

cmd_scan() {
  _target="" _threshold_mb=100 _no_sudo=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --target)
        [ $# -ge 2 ] || die "--target requires an argument"
        _target="$2"; shift 2 ;;
      --cache-threshold)
        [ $# -ge 2 ] || die "--cache-threshold requires an argument"
        _threshold_mb="$2"; shift 2 ;;
      --no-sudo) _no_sudo=1; shift ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  _threshold=$((_threshold_mb * 1048576))
  _grand_total=0

  info "Cleanup scan:"
  printf "\n"

  _targets="packages trash journal docker thumbnails downloads cache"
  if [ -n "$_target" ]; then
    _targets="$_target"
  fi

  for _t in $_targets; do
    case "$_t" in
      packages)
        if [ "$_no_sudo" -eq 1 ] && packages_needs_sudo; then
          continue
        fi
        _size=$(scan_packages)
        ;;
      trash)      _size=$(scan_trash) ;;
      journal)
        if [ "$_no_sudo" -eq 1 ]; then
          continue
        fi
        _size=$(scan_journal)
        ;;
      docker)     _size=$(scan_docker) ;;
      thumbnails) _size=$(scan_thumbnails) ;;
      downloads)  _size=$(scan_downloads) ;;
      cache)      _size=$(scan_cache "$_threshold") ;;
      *) die "Unknown target: $_t" ;;
    esac

    _size="${_size:-0}"
    if [ "$_size" -gt 0 ] 2>/dev/null; then
      printf "  %-25s %s\n" "$_t" "$(human_size "$_size")"
      _grand_total=$((_grand_total + _size))
    fi
  done

  printf "\n"
  if [ "$_grand_total" -gt 0 ]; then
    info "Total reclaimable: $(human_size "$_grand_total")"
  else
    info "Nothing to clean."
  fi
}

cmd_run() {
  _no_confirm=0 _target="" _threshold_mb=100 _no_sudo=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --no-confirm) _no_confirm=1; shift ;;
      --target)
        [ $# -ge 2 ] || die "--target requires an argument"
        _target="$2"; shift 2 ;;
      --cache-threshold)
        [ $# -ge 2 ] || die "--cache-threshold requires an argument"
        _threshold_mb="$2"; shift 2 ;;
      --no-sudo) _no_sudo=1; shift ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  _threshold=$((_threshold_mb * 1048576))

  _targets="packages trash journal docker thumbnails downloads cache"
  if [ -n "$_target" ]; then
    _targets="$_target"
  fi

  for _t in $_targets; do
    # Check sudo requirement
    case "$_t" in
      packages)
        if [ "$_no_sudo" -eq 1 ] && packages_needs_sudo; then
          info "Skipping packages (requires sudo)"
          continue
        fi
        ;;
      journal)
        if [ "$_no_sudo" -eq 1 ]; then
          info "Skipping journal (requires sudo)"
          continue
        fi
        ;;
    esac

    # Scan first
    case "$_t" in
      packages)   _size=$(scan_packages) ;;
      trash)      _size=$(scan_trash) ;;
      journal)    _size=$(scan_journal) ;;
      docker)     _size=$(scan_docker) ;;
      thumbnails) _size=$(scan_thumbnails) ;;
      downloads)  _size=$(scan_downloads) ;;
      cache)      _size=$(scan_cache "$_threshold") ;;
      *) die "Unknown target: $_t" ;;
    esac

    _size="${_size:-0}"
    [ "$_size" -gt 0 ] 2>/dev/null || continue

    if [ "$_no_confirm" -eq 0 ]; then
      confirm "Clean $_t ($(human_size "$_size"))?" || continue
    fi

    case "$_t" in
      packages)   clean_packages ;;
      trash)      clean_trash ;;
      journal)    clean_journal ;;
      docker)     clean_docker ;;
      thumbnails) clean_thumbnails ;;
      downloads)  clean_downloads ;;
      cache)      clean_cache "$_threshold" ;;
    esac
  done
}

# ── Main dispatch ──

if [ $# -lt 1 ]; then
  cmd_scan
  exit 0
fi

cmd="$1"
shift

case "$cmd" in
  scan)             cmd_scan "$@" ;;
  run)              cmd_run "$@" ;;
  help|-h|--help)   show_help ;;
  --version)        printf '%s\n' "$VERSION"; exit 0 ;;
  *)
    die "Unknown command: $cmd. Run 'cleanup help' for usage."
    ;;
esac
