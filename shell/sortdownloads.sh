#!/bin/sh

# Script to sort Downloads folder into organized subdirectories
# Author: Manoah Bernier

set -eu

VERSION="1.0.0"

# ── Constants ──

RESET="\033[0m"
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"

SKIP_EXTENSIONS="part crdownload download"

TIMER_NAME="sortdownloads"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

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

# ── Locale ──

detect_locale() {
  _loc="${LC_ALL:-${LANG:-}}"
  case "$_loc" in
    fr_*) printf "fr" ;;
    *)    printf "en" ;;
  esac
}

detect_downloads_dir() {
  if command -v xdg-user-dir >/dev/null 2>&1; then
    _dir=$(xdg-user-dir DOWNLOAD 2>/dev/null || true)
    if [ -n "$_dir" ] && [ -d "$_dir" ]; then
      printf "%s" "$_dir"
      return
    fi
  fi
  if [ -d "$HOME/Downloads" ]; then
    printf "%s" "$HOME/Downloads"
  elif [ -d "$HOME/Téléchargements" ]; then
    printf "%s" "$HOME/Téléchargements"
  else
    printf "%s" "$HOME/Downloads"
  fi
}

translate_category() {
  _cat="$1"
  _locale="$2"
  if [ "$_locale" = "fr" ]; then
    case "$_cat" in
      Videos)       printf "Vidéos" ;;
      Music)        printf "Musique" ;;
      Programs)     printf "Programmes" ;;
      Fonts)        printf "Polices" ;;
      "Disk Images") printf "Images disque" ;;
      Other)        printf "Autres" ;;
      eBooks)       printf "Livres" ;;
      Text)         printf "Texte" ;;
      Data)         printf "Données" ;;
      *)            printf "%s" "$_cat" ;;
    esac
  else
    printf "%s" "$_cat"
  fi
}

# ── Extension mapping ──

get_extension() {
  _fname="$1"
  _base=$(basename "$_fname")

  # Compound extensions
  case "$_base" in
    *.tar.gz)  printf "tgz";  return ;;
    *.tar.bz2) printf "tbz2"; return ;;
    *.tar.xz)  printf "txz";  return ;;
    *.tar.zst) printf "tzst"; return ;;
  esac

  # Simple extension
  case "$_base" in
    *.*) _ext="${_base##*.}"; printf "%s" "$_ext" | tr '[:upper:]' '[:lower:]' ;;
    *)   printf "" ;;
  esac
}

get_category() {
  _ext="$1"
  case "$_ext" in
    # Documents
    pdf)                                          printf "Documents/PDFs" ;;
    doc|docx|odt|rtf|pages)                       printf "Documents/Word" ;;
    xls|xlsx|ods|numbers|csv|tsv)                 printf "Documents/Excel" ;;
    ppt|pptx|odp|keynote)                         printf "Documents/PowerPoint" ;;
    txt|tex)                                      printf "Documents/Text" ;;
    md|rst)                                       printf "Documents/Markdown" ;;
    epub|mobi|djvu)                               printf "Documents/eBooks" ;;
    json|xml|yaml|yml|toml|ini|conf|cfg|sql|db|sqlite) printf "Documents/Data" ;;
    stl|obj|fbx|blend|step|stp)                   printf "Documents/3D" ;;

    # Images
    jpg|jpeg)                                     printf "Images/JPG" ;;
    png)                                          printf "Images/PNG" ;;
    gif)                                          printf "Images/GIF" ;;
    svg)                                          printf "Images/SVG" ;;
    webp)                                         printf "Images/WebP" ;;
    raw|cr2|nef|arw)                              printf "Images/RAW" ;;
    psd|ai|xcf|sketch|fig|xd)                    printf "Images/Design" ;;
    bmp|tiff|tif|ico|heic|heif)                   printf "Images/Other" ;;

    # Videos
    mp4)                                          printf "Videos/MP4" ;;
    mkv)                                          printf "Videos/MKV" ;;
    avi)                                          printf "Videos/AVI" ;;
    webm)                                         printf "Videos/WebM" ;;
    mov|wmv|flv|m4v|mpg|mpeg|3gp|ogv|ts)         printf "Videos/Other" ;;

    # Music
    mp3)                                          printf "Music/MP3" ;;
    flac)                                         printf "Music/FLAC" ;;
    wav)                                          printf "Music/WAV" ;;
    ogg)                                          printf "Music/OGG" ;;
    aac|wma|m4a|opus|aiff|mid|midi)               printf "Music/Other" ;;

    # Archives
    zip)                                          printf "Archives/ZIP" ;;
    tar|tgz|tbz2|txz|tzst)                       printf "Archives/TAR" ;;
    7z)                                           printf "Archives/7Z" ;;
    rar)                                          printf "Archives/RAR" ;;
    gz|bz2|xz|zst|cab|lz|lzma)                   printf "Archives/Other" ;;

    # Programs
    deb)                                          printf "Programs/DEB" ;;
    rpm)                                          printf "Programs/RPM" ;;
    appimage)                                     printf "Programs/AppImage" ;;
    flatpakref)                                   printf "Programs/Flatpak" ;;
    snap|dmg|msi|exe|pkg|apk)                     printf "Programs/Other" ;;

    # Scripts
    sh|bash|zsh)                                  printf "Scripts/Shell" ;;
    py)                                           printf "Scripts/Python" ;;
    js|ts|rb|pl|lua|html|htm|css|php|asp|jsp)     printf "Scripts/Web" ;;

    # Fonts (no subcategory)
    ttf|otf|woff|woff2|eot)                       printf "Fonts" ;;

    # Torrents (no subcategory)
    torrent)                                      printf "Torrents" ;;

    # Disk Images
    iso)                                          printf "Disk Images/ISO" ;;
    img)                                          printf "Disk Images/IMG" ;;
    bin|cue|nrg|vdi|vmdk|qcow2)                   printf "Disk Images/Other" ;;

    # Unknown
    *)                                            printf "Other" ;;
  esac
}

# ── File processing ──

should_skip() {
  _file="$1"
  _basename=$(basename "$_file")

  # Skip directories
  [ -f "$_file" ] || return 0

  # Skip symlinks
  [ ! -L "$_file" ] || return 0

  # Skip dotfiles
  case "$_basename" in
    .*) return 0 ;;
  esac

  # Skip in-progress downloads
  _ext=$(get_extension "$_file")
  for _skip in $SKIP_EXTENSIONS; do
    [ "$_ext" = "$_skip" ] && return 0
  done

  return 1
}

resolve_duplicate() {
  _target="$1"
  if [ ! -e "$_target" ]; then
    printf "%s" "$_target"
    return
  fi

  _dir=$(dirname "$_target")
  _base=$(basename "$_target")

  # Split name and extension
  case "$_base" in
    *.*)
      _name="${_base%.*}"
      _suffix=".${_base##*.}"
      ;;
    *)
      _name="$_base"
      _suffix=""
      ;;
  esac

  _i=1
  while true; do
    _candidate="$_dir/${_name} (${_i})${_suffix}"
    if [ ! -e "$_candidate" ]; then
      printf "%s" "$_candidate"
      return
    fi
    _i=$((_i + 1))
  done
}

move_file() {
  _file="$1"
  _downloads_dir="$2"
  _locale="$3"
  _dry_run="$4"
  _verbose="$5"

  _ext=$(get_extension "$_file")
  if [ -z "$_ext" ]; then
    _result="Other"
  else
    _result=$(get_category "$_ext")
  fi

  _category="${_result%%/*}"
  _subcategory="${_result#*/}"
  [ "$_subcategory" = "$_category" ] && _subcategory=""

  # Translate main category
  _translated=$(translate_category "$_category" "$_locale")

  # Build target directory
  if [ -n "$_subcategory" ]; then
    # Translate subcategory if applicable
    _translated_sub=$(translate_category "$_subcategory" "$_locale")
    _target_dir="$_downloads_dir/$_translated/$_translated_sub"
  else
    _target_dir="$_downloads_dir/$_translated"
  fi

  _basename=$(basename "$_file")
  _target=$(resolve_duplicate "$_target_dir/$_basename")

  if [ "$_dry_run" -eq 1 ]; then
    printf "%s → %s\n" "$_basename" "$_target_dir/"
    return 0
  fi

  mkdir -p "$_target_dir"
  mv "$_file" "$_target"

  if [ "$_verbose" -eq 1 ]; then
    printf "%s → %s\n" "$_basename" "$_target"
  fi
}

# ── Scheduling ──

has_systemd_user() {
  systemctl --user status >/dev/null 2>&1
}

compute_calendar_spec() {
  _freq="$1"
  _at="$2"
  _day="$3"
  _range="$4"

  case "$_freq" in
    daily)
      printf "*-*-* %s:00" "$_at"
      ;;
    weekly)
      if [ -n "$_day" ]; then
        printf "%s *-*-* %s:00" "$_day" "$_at"
      elif [ "$_range" = "end" ]; then
        printf "Sun *-*-* %s:00" "$_at"
      else
        printf "Mon *-*-* %s:00" "$_at"
      fi
      ;;
    monthly)
      if [ -n "$_day" ]; then
        printf "*-*-%s %s:00" "$_day" "$_at"
      elif [ "$_range" = "end" ]; then
        printf "*-*-28 %s:00" "$_at"
      else
        printf "*-*-01 %s:00" "$_at"
      fi
      ;;
  esac
}

compute_cron_spec() {
  _freq="$1"
  _at="$2"
  _day="$3"
  _range="$4"

  _hour="${_at%%:*}"
  _min="${_at#*:}"

  case "$_freq" in
    daily)
      printf "%s %s * * *" "$_min" "$_hour"
      ;;
    weekly)
      if [ -n "$_day" ]; then
        _dow=$(day_to_cron "$_day")
        printf "%s %s * * %s" "$_min" "$_hour" "$_dow"
      elif [ "$_range" = "end" ]; then
        printf "%s %s * * 0" "$_min" "$_hour"
      else
        printf "%s %s * * 1" "$_min" "$_hour"
      fi
      ;;
    monthly)
      if [ -n "$_day" ]; then
        printf "%s %s %s * *" "$_min" "$_hour" "$_day"
      elif [ "$_range" = "end" ]; then
        printf "%s %s 28 * *" "$_min" "$_hour"
      else
        printf "%s %s 1 * *" "$_min" "$_hour"
      fi
      ;;
  esac
}

day_to_cron() {
  case "$1" in
    mon|Mon) printf "1" ;;
    tue|Tue) printf "2" ;;
    wed|Wed) printf "3" ;;
    thu|Thu) printf "4" ;;
    fri|Fri) printf "5" ;;
    sat|Sat) printf "6" ;;
    sun|Sun) printf "0" ;;
    *)       printf "%s" "$1" ;;
  esac
}

install_systemd_timer() {
  _calendar="$1"
  _script_path="$2"

  mkdir -p "$SYSTEMD_USER_DIR"

  cat > "$SYSTEMD_USER_DIR/$TIMER_NAME.service" <<EOF
[Unit]
Description=Sort Downloads folder

[Service]
Type=oneshot
ExecStart=$_script_path now
EOF

  cat > "$SYSTEMD_USER_DIR/$TIMER_NAME.timer" <<EOF
[Unit]
Description=Sort Downloads folder periodically

[Timer]
OnCalendar=$_calendar
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now "$TIMER_NAME.timer"
  success "Installed systemd timer: $_calendar"
}

remove_systemd_timer() {
  if systemctl --user is-enabled "$TIMER_NAME.timer" >/dev/null 2>&1; then
    systemctl --user disable --now "$TIMER_NAME.timer"
  fi
  rm -f "$SYSTEMD_USER_DIR/$TIMER_NAME.service"
  rm -f "$SYSTEMD_USER_DIR/$TIMER_NAME.timer"
  systemctl --user daemon-reload
  success "Removed systemd timer"
}

install_cron_job() {
  _cron_spec="$1"
  _script_path="$2"
  _line="$_cron_spec $_script_path now # sortdownloads"

  ( crontab -l 2>/dev/null | grep -v "# sortdownloads"; printf "%s\n" "$_line" ) | crontab -
  success "Installed cron job: $_cron_spec"
}

remove_cron_job() {
  ( crontab -l 2>/dev/null | grep -v "# sortdownloads" ) | crontab -
  success "Removed cron job"
}

# ── Help ──

show_help() {
  prog=$(basename "$0")
  cat <<EOF
$prog – Sort Downloads folder into organized subdirectories

Usage:
  $prog <command> [options]

Commands:
  now              Sort files immediately
  schedule FREQ    Schedule periodic sorting (daily, weekly, monthly)
  status           Show current schedule status
  unschedule       Remove scheduled sorting
  help, -h         Show this help message

Now options:
  --dry-run        Show what would be moved without moving
  --dir DIR        Use DIR instead of detected Downloads folder
  --verbose        Show each file as it is moved

Schedule options:
  --at HH:MM       Time of day to run (default: 09:00)
  --on DAY         Specific day (mon-sun for weekly, 1-28 for monthly)
  --start          Start of range (Mon for weekly, 1st for monthly)
  --end            End of range (Sun for weekly, 28th for monthly)

Examples:
  $prog now --dry-run
  $prog now --verbose
  $prog schedule daily --at 08:00
  $prog schedule weekly --on fri --at 18:00
  $prog schedule monthly --start --at 10:00
  $prog status
  $prog unschedule
EOF
  exit 0
}

# ── Commands ──

cmd_now() {
  _dry_run=0
  _verbose=0
  _dir=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) _dry_run=1; shift ;;
      --verbose) _verbose=1; shift ;;
      --dir)
        [ $# -ge 2 ] || die "Missing argument for --dir"
        _dir="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  _locale=$(detect_locale)

  if [ -n "$_dir" ]; then
    _downloads="$_dir"
  else
    _downloads=$(detect_downloads_dir)
  fi

  [ -d "$_downloads" ] || die "Downloads directory not found: $_downloads"

  _count=0
  _moved=0

  for _file in "$_downloads"/*; do
    # Handle empty directory (glob returns literal pattern)
    [ -e "$_file" ] || [ -L "$_file" ] || continue
    _count=$((_count + 1))

    if should_skip "$_file"; then
      continue
    fi

    move_file "$_file" "$_downloads" "$_locale" "$_dry_run" "$_verbose"
    _moved=$((_moved + 1))
  done

  if [ "$_count" -eq 0 ]; then
    info "Downloads folder is empty."
    return 0
  fi

  if [ "$_dry_run" -eq 1 ]; then
    info "Dry run complete: $_moved file(s) would be moved."
  else
    success "Sorted $_moved file(s)."
  fi
}

cmd_schedule() {
  [ $# -ge 1 ] || die "Missing frequency. Usage: schedule daily|weekly|monthly"

  _freq="$1"; shift
  case "$_freq" in
    daily|weekly|monthly) ;;
    *) die "Invalid frequency: $_freq. Use daily, weekly, or monthly." ;;
  esac

  _at="09:00"
  _day=""
  _range="start"
  _has_on=0
  _has_range=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --at)
        [ $# -ge 2 ] || die "Missing argument for --at"
        _at="$2"
        # Validate HH:MM format
        case "$_at" in
          [0-9][0-9]:[0-9][0-9]) ;;
          *) die "Invalid time format: $_at. Use HH:MM." ;;
        esac
        _hour="${_at%%:*}"
        _min="${_at#*:}"
        [ "$_hour" -le 23 ] 2>/dev/null || die "Invalid hour: $_hour"
        [ "$_min" -le 59 ] 2>/dev/null || die "Invalid minute: $_min"
        shift 2
        ;;
      --on)
        [ $# -ge 2 ] || die "Missing argument for --on"
        [ "$_has_range" -eq 0 ] || die "--on and --start/--end are mutually exclusive"
        _has_on=1
        _day="$2"
        # Validate day
        if [ "$_freq" = "weekly" ]; then
          case "$_day" in
            mon|tue|wed|thu|fri|sat|sun|Mon|Tue|Wed|Thu|Fri|Sat|Sun) ;;
            *) die "Invalid day: $_day. Use mon-sun." ;;
          esac
        elif [ "$_freq" = "monthly" ]; then
          case "$_day" in
            *[!0-9]*) die "Invalid day: $_day. Use 1-28." ;;
          esac
          [ "$_day" -ge 1 ] 2>/dev/null && [ "$_day" -le 28 ] 2>/dev/null || die "Invalid day: $_day. Use 1-28."
        else
          warn "--on is ignored for daily frequency"
          _day=""
        fi
        shift 2
        ;;
      --start)
        [ "$_has_on" -eq 0 ] || die "--on and --start/--end are mutually exclusive"
        _has_range=1
        if [ "$_freq" = "daily" ]; then
          warn "--start is ignored for daily frequency"
        else
          _range="start"
        fi
        shift
        ;;
      --end)
        [ "$_has_on" -eq 0 ] || die "--on and --start/--end are mutually exclusive"
        _has_range=1
        if [ "$_freq" = "daily" ]; then
          warn "--end is ignored for daily frequency"
        else
          _range="end"
        fi
        shift
        ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  # Resolve script path
  _script_path=$(readlink -f "$0" 2>/dev/null || printf "%s" "$0")

  if has_systemd_user; then
    _calendar=$(compute_calendar_spec "$_freq" "$_at" "$_day" "$_range")
    install_systemd_timer "$_calendar" "$_script_path"
  else
    _cron=$(compute_cron_spec "$_freq" "$_at" "$_day" "$_range")
    install_cron_job "$_cron" "$_script_path"
  fi
}

cmd_status() {
  if has_systemd_user; then
    if systemctl --user is-enabled "$TIMER_NAME.timer" >/dev/null 2>&1; then
      info "Scheduling: systemd timer (enabled)"
      systemctl --user status "$TIMER_NAME.timer" --no-pager 2>/dev/null || true
    else
      info "No systemd timer configured."
    fi
  else
    _cron=$(crontab -l 2>/dev/null | grep "# sortdownloads" || true)
    if [ -n "$_cron" ]; then
      info "Scheduling: cron"
      printf "%s\n" "$_cron"
    else
      info "No schedule configured."
    fi
  fi
}

cmd_unschedule() {
  if has_systemd_user; then
    if systemctl --user is-enabled "$TIMER_NAME.timer" >/dev/null 2>&1; then
      remove_systemd_timer
    else
      info "No systemd timer to remove."
    fi
  else
    _cron=$(crontab -l 2>/dev/null | grep "# sortdownloads" || true)
    if [ -n "$_cron" ]; then
      remove_cron_job
    else
      info "No cron job to remove."
    fi
  fi
}

# ── Main dispatch ──

if [ $# -lt 1 ]; then
  show_help
fi

cmd="$1"
shift

case "$cmd" in
  now)              cmd_now "$@" ;;
  schedule)         cmd_schedule "$@" ;;
  status)           cmd_status "$@" ;;
  unschedule)       cmd_unschedule "$@" ;;
  help|-h|--help)   show_help ;;
  --version)        printf '%s\n' "$VERSION"; exit 0 ;;
  *)
    printf "Unknown command: %s\n\n" "$cmd"
    show_help
    ;;
esac
