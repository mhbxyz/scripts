#!/bin/sh

# Script to backup home directory to an external drive
# Author: Manoah Bernier

set -eu

VERSION="1.0.0"

# ── Constants ──

RESET="\033[0m"
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"

DEFAULT_EXCLUDES=".cache .local node_modules __pycache__ .venv .npm .gradle .m2 .cargo .rustup .lmstudio Downloads Videos Games"
MOUNT_BASES="${HOMEBACKUP_MOUNT_BASES:-/run/media/$(id -un) /media/$(id -un) /media /mnt}"

# ── Temp file cleanup ──

TMPFILES=""
COMP_PID=""
KEEP_PARTIAL=0
BACKUP_FILE=""

cleanup() {
  if [ -n "$COMP_PID" ]; then
    kill "$COMP_PID" 2>/dev/null || true
    wait "$COMP_PID" 2>/dev/null || true
    COMP_PID=""
  fi
  if [ "$KEEP_PARTIAL" -eq 0 ] && [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
    rm -f "$BACKUP_FILE"
  fi
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

format_bytes() {
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec "$1"
  else
    bytes="$1"
    if [ "$bytes" -ge 1073741824 ]; then
      printf "%d.%dG" "$((bytes / 1073741824))" "$(((bytes % 1073741824) * 10 / 1073741824))"
    elif [ "$bytes" -ge 1048576 ]; then
      printf "%d.%dM" "$((bytes / 1048576))" "$(((bytes % 1048576) * 10 / 1048576))"
    elif [ "$bytes" -ge 1024 ]; then
      printf "%d.%dK" "$((bytes / 1024))" "$(((bytes % 1024) * 10 / 1024))"
    else
      printf "%dB" "$bytes"
    fi
  fi
}

# ── Domain helpers ──

list_drives() {
  for base in $MOUNT_BASES; do
    if [ -d "$base" ]; then
      for d in "$base"/*/; do
        [ -d "$d" ] || continue
        name=$(basename "$d")
        printf "%s\t%s\n" "$name" "$d"
      done
    fi
  done
}

resolve_drive() {
  target="$1"
  for base in $MOUNT_BASES; do
    if [ -d "$base/$target" ]; then
      printf "%s" "$base/$target"
      return 0
    fi
  done
  return 1
}

select_drive() {
  drives=$(list_drives)
  if [ -z "$drives" ]; then
    die "No mounted drives found."
  fi

  printf "\n${BLUE}Available drives:${RESET}\n"
  i=1
  printf "%s\n" "$drives" | while IFS='	' read -r name path; do
    avail=$(df -P "$path" | awk 'NR==2 { print $4 }')
    avail_hr=$(format_bytes "$((avail * 1024))")
    total=$(df -P "$path" | awk 'NR==2 { print $2 }')
    total_hr=$(format_bytes "$((total * 1024))")
    printf "  %d) %s  [%s / %s free]  %s\n" "$i" "$name" "$avail_hr" "$total_hr" "$path"
    i=$((i + 1))
  done

  count=$(printf "%s\n" "$drives" | wc -l)
  printf "\nSelect drive [1-%d]: " "$count"
  read -r choice
  case "${choice:-}" in
    ''|*[!0-9]*) die "Invalid selection." ;;
  esac
  if [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
    die "Invalid selection."
  fi

  printf "%s\n" "$drives" | awk -F'\t' "NR==$choice { print \$2 }"
}

build_exclude_file() {
  excludes="$1"
  exclude_file="$2"

  tmpfile=$(mktemp)
  register_tmp "$tmpfile"

  # Write inline excludes
  for ex in $excludes; do
    printf "%s\n" "$ex" >> "$tmpfile"
  done

  # Append from exclude file if provided
  if [ -n "$exclude_file" ] && [ -f "$exclude_file" ]; then
    cat "$exclude_file" >> "$tmpfile"
  fi

  printf "%s" "$tmpfile"
}

count_files() {
  exclude_file="$1"
  if [ -s "$exclude_file" ]; then
    pattern=$(awk '{ printf "%s%s", sep, $0; sep="|" }' "$exclude_file")
    find "$HOME" -mindepth 1 2>/dev/null | grep -v -E "$pattern" | wc -l | tr -d ' '
  else
    find "$HOME" -mindepth 1 2>/dev/null | wc -l | tr -d ' '
  fi
}

check_disk_space() {
  dest_path="$1"
  avail=$(df -P "$dest_path" | awk 'NR==2 { print $4 }')
  avail_bytes=$((avail * 1024))
  # Rough estimate: source dir size
  src_size=$(du -sk "$HOME" 2>/dev/null | awk '{ print $1 }')
  src_bytes=$((src_size * 1024))
  printf "Estimated source size: %s\n" "$(format_bytes "$src_bytes")"
  printf "Available space:       %s\n" "$(format_bytes "$avail_bytes")"
  if [ "$avail_bytes" -lt "$src_bytes" ]; then
    warn "Available space may be insufficient."
  fi
}

get_compress_cmd() {
  case "$1" in
    gzip) printf "gzip" ;;
    xz)   printf "xz" ;;
    zstd) printf "zstd" ;;
    none) printf "cat" ;;
    *)    die "Invalid compression type: $1" ;;
  esac
}

get_compress_ext() {
  case "$1" in
    gzip) printf ".gz" ;;
    xz)   printf ".xz" ;;
    zstd) printf ".zst" ;;
    none) printf "" ;;
  esac
}

show_progress() {
  total="$1"
  count=0
  spinner='/-\|'
  i=0
  cols=$(tput cols 2>/dev/null || printf "80")
  prefix_len=30
  max_fname=$((cols - prefix_len))
  [ "$max_fname" -lt 10 ] && max_fname=10

  while IFS= read -r filename; do
    count=$((count + 1))
    if [ "$total" -gt 0 ]; then
      percent=$((count * 100 / total))
      [ "$percent" -gt 100 ] && percent=100
    else
      percent=0
    fi
    c=$(printf "%s" "$spinner" | cut -c $(((i % 4) + 1)))
    i=$((i + 1))

    display_name="$filename"
    fname_len=${#display_name}
    if [ "$fname_len" -gt "$max_fname" ]; then
      display_name="...$(printf "%s" "$display_name" | tail -c "$max_fname")"
    fi

    printf "\r\033[K${GREEN}[%c] [%d/%d] [%d%%]${RESET}  %s" "$c" "$count" "$total" "$percent" "$display_name"
  done
  printf "\n"
}

# ── Help ──

show_help() {
  prog=$(basename "$0")
  cat <<EOF
$prog – Backup home directory to an external drive

Usage:
  $prog <command> [options]

Commands:
  run              Create a backup of the home directory
  list, ls         List mounted drives with available space
  help, -h         Show this help message

Run options:
  --drive NAME         Target drive name (skip interactive selection)
  --compress TYPE      Compression: gzip (default), xz, zstd, none
  --default-excludes   Use default exclude list
  --excludes "A B"     Replace all excludes with specified patterns
  --add-excludes "A B" Add to default excludes
  --exclude-file FILE  File containing exclude patterns (one per line)
  --verify             Verify archive after creation
  --keep-partial       Keep incomplete archive if interrupted
  --dry-run            List files without creating an archive
  --backup-dir DIR     Subdirectory on drive (default: backups)

Examples:
  $prog run --default-excludes --compress zstd --verify
  $prog run --drive MyDrive --default-excludes --add-excludes "Music"
  $prog run --dry-run --default-excludes
  $prog list
EOF
  exit 0
}

# ── Commands ──

cmd_run() {
  drive_name=""
  compress="gzip"
  excludes=""
  add_excludes=""
  excludes_mode="none"
  exclude_file=""
  verify=0
  dry_run=0
  backup_dir="backups"

  while [ $# -gt 0 ]; do
    case "$1" in
      --drive)
        [ $# -ge 2 ] || die "Missing argument for --drive"
        drive_name="$2"; shift 2 ;;
      --compress)
        [ $# -ge 2 ] || die "Missing argument for --compress"
        case "$2" in
          gzip|xz|zstd|none) compress="$2" ;;
          *) die "Invalid compression type: $2. Use gzip, xz, zstd, or none." ;;
        esac
        shift 2 ;;
      --default-excludes)
        if [ "$excludes_mode" != "manual" ]; then
          excludes="$DEFAULT_EXCLUDES"
          excludes_mode="default"
        fi
        shift ;;
      --excludes)
        [ $# -ge 2 ] || die "Missing argument for --excludes"
        excludes="$2"; excludes_mode="manual"; shift 2 ;;
      --add-excludes)
        [ $# -ge 2 ] || die "Missing argument for --add-excludes"
        add_excludes="$add_excludes $2"; shift 2 ;;
      --exclude-file)
        [ $# -ge 2 ] || die "Missing argument for --exclude-file"
        [ -f "$2" ] || die "Exclude file not found: $2"
        exclude_file="$2"; shift 2 ;;
      --verify)       verify=1; shift ;;
      --keep-partial) KEEP_PARTIAL=1; shift ;;
      --dry-run)      dry_run=1; shift ;;
      --backup-dir)
        [ $# -ge 2 ] || die "Missing argument for --backup-dir"
        backup_dir="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  # Resolve drive
  if [ -n "$drive_name" ]; then
    dest_path=$(resolve_drive "$drive_name") || die "Drive not found: $drive_name"
  else
    dest_path=$(select_drive)
    [ -n "$dest_path" ] || die "No drive selected."
  fi

  # Remove trailing slash
  dest_path=$(printf "%s" "$dest_path" | sed 's|/$||')

  dest_dir="$dest_path/$backup_dir"
  mkdir -p "$dest_dir"

  # Build final excludes
  if [ "$excludes_mode" = "manual" ]; then
    final_excludes="$excludes"
  elif [ "$excludes_mode" = "default" ]; then
    final_excludes="$excludes $add_excludes"
  else
    final_excludes="$add_excludes"
  fi

  # Build exclude file for tar
  ef=$(build_exclude_file "$final_excludes" "$exclude_file")

  if [ -s "$ef" ]; then
    info "Excluding:"
    while IFS= read -r pattern; do
      [ -n "$pattern" ] && printf "  - %s\n" "$pattern"
    done < "$ef"
  fi

  # Dry run
  if [ "$dry_run" -eq 1 ]; then
    info "Dry run — files that would be archived:"
    tar -cvf /dev/null --exclude-from="$ef" -C "$HOME" . 2>&1
    return 0
  fi

  # Count files
  info "Counting files..."
  total=$(count_files "$ef")
  [ "$total" -eq 0 ] && die "Nothing to backup."
  printf "Files to archive: ~%s\n" "$total"

  # Disk space check
  check_disk_space "$dest_path"

  # Compression setup
  comp_cmd=$(get_compress_cmd "$compress")
  comp_ext=$(get_compress_ext "$compress")
  if [ "$comp_cmd" != "cat" ]; then
    check_dep "$comp_cmd"
  fi

  filename="home_backup_$(date +%Y%m%d_%H%M%S).tar${comp_ext}"
  BACKUP_FILE="$dest_dir/$filename"

  # Create FIFO
  fifo=$(mktemp -u)
  mkfifo "$fifo"
  register_tmp "$fifo"

  # Start compression in background
  $comp_cmd < "$fifo" > "$BACKUP_FILE" &
  COMP_PID=$!

  # Archive
  info "Starting backup to $BACKUP_FILE..."
  tar -cf "$fifo" --exclude-from="$ef" -C "$HOME" . -v 2>&1 | show_progress "$total"

  # Wait for compression to finish
  wait "$COMP_PID"
  result=$?
  COMP_PID=""

  if [ "$result" -ne 0 ]; then
    die "Compression failed (exit code: $result)."
  fi

  # Mark backup complete — don't remove on cleanup
  BACKUP_FILE=""
  success "Backup completed: $dest_dir/$filename"

  # Verify
  if [ "$verify" -eq 1 ]; then
    info "Verifying archive..."
    if tar -tf "$dest_dir/$filename" >/dev/null 2>&1; then
      success "Verification OK"
    else
      die "Verification failed."
    fi
  fi
}

cmd_list() {
  drives=$(list_drives)
  if [ -z "$drives" ]; then
    die "No mounted drives found."
  fi

  printf "\n${BLUE}Mounted drives:${RESET}\n"
  printf "%s\n" "$drives" | while IFS='	' read -r name path; do
    avail=$(df -P "$path" | awk 'NR==2 { print $4 }')
    avail_hr=$(format_bytes "$((avail * 1024))")
    total=$(df -P "$path" | awk 'NR==2 { print $2 }')
    total_hr=$(format_bytes "$((total * 1024))")
    printf "  %s  [%s / %s free]  %s\n" "$name" "$avail_hr" "$total_hr" "$path"
  done
}

# ── Main dispatch ──

check_dep tar
check_dep df

if [ $# -lt 1 ]; then
  show_help
fi

cmd="$1"
shift

case "$cmd" in
  run)            cmd_run "$@" ;;
  list|ls)        cmd_list "$@" ;;
  help|-h|--help) show_help ;;
  --version)      printf '%s\n' "$VERSION"; exit 0 ;;
  *)
    printf "Unknown command: %s\n\n" "$cmd"
    show_help
    ;;
esac
