#!/bin/sh

# Script to generate and manage GPG keys
# Author: Manoah Bernier

set -eu

VERSION="1.0.0"

# ── Constants ──

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

copy_to_clipboard() {
  if command -v pbcopy >/dev/null 2>&1; then
    pbcopy
  elif command -v wl-copy >/dev/null 2>&1; then
    wl-copy
  elif command -v xclip >/dev/null 2>&1; then
    xclip -sel clip
  elif command -v xsel >/dev/null 2>&1; then
    xsel --clipboard --input
  elif command -v clip >/dev/null 2>&1; then
    clip
  else
    warn "No clipboard tool found (pbcopy/wl-copy/xclip/xsel/clip)."
    return 1
  fi
}

# select_key — interactive key selection
# Usage: select_key [identifier] [--secret]
# Prints the selected long key ID to stdout
select_key() {
  identifier=""
  list_secret="--list-secret-keys"

  for arg in "$@"; do
    case "$arg" in
      --public) list_secret="--list-keys" ;;
      *) identifier="$arg" ;;
    esac
  done

  # If an identifier is provided, resolve it directly
  if [ -n "$identifier" ]; then
    keyid=$(gpg $list_secret --with-colons --keyid-format long 2>/dev/null \
      | awk -F: '/^sec:|^pub:/ { id=$5 } /^uid:/ { if (id != "" && ($10 ~ /'"$identifier"'/)) { print id; id="" } }')
    if [ -z "$keyid" ]; then
      die "No key found matching '$identifier'."
    fi
    # If multiple matches, take the first
    printf "%s" "$keyid" | head -n 1
    return 0
  fi

  # Collect keys
  tmpkeys=$(mktemp)
  register_tmp "$tmpkeys"

  gpg $list_secret --with-colons --keyid-format long 2>/dev/null \
    | awk -F: '
      /^sec:|^pub:/ { keyid=$5; algo=$4; created=$6; expires=$7 }
      /^uid:/ {
        if (keyid != "") {
          print keyid "\t" algo "\t" created "\t" expires "\t" $10
          keyid=""
        }
      }
    ' > "$tmpkeys"

  count=$(wc -l < "$tmpkeys" | tr -d ' ')

  if [ "$count" -eq 0 ]; then
    die "No GPG keys found. Run '$(basename "$0") generate' first."
  fi

  if [ "$count" -eq 1 ]; then
    awk -F'\t' '{ print $1 }' "$tmpkeys"
    return 0
  fi

  # Multiple keys — interactive selection
  printf "\n${BLUE}Available keys:${RESET}\n"
  i=1
  while IFS='	' read -r kid algo created expires uid; do
    created_fmt=$(date -d "@$created" "+%Y-%m-%d" 2>/dev/null || printf "%s" "$created")
    if [ -n "$expires" ] && [ "$expires" != "0" ]; then
      expires_fmt=$(date -d "@$expires" "+%Y-%m-%d" 2>/dev/null || printf "%s" "$expires")
    else
      expires_fmt="never"
    fi
    printf "  %d) %s  %s  [%s → %s]\n" "$i" "$kid" "$uid" "$created_fmt" "$expires_fmt"
    i=$((i + 1))
  done < "$tmpkeys"

  printf "\nSelect key [1-%d]: " "$count"
  read -r choice
  if [ -z "$choice" ] || [ "$choice" -lt 1 ] 2>/dev/null || [ "$choice" -gt "$count" ] 2>/dev/null; then
    die "Invalid selection."
  fi

  awk -F'\t' "NR==$choice { print \$1 }" "$tmpkeys"
}

# ── Help ──

show_help() {
  prog=$(basename "$0")
  cat <<EOF
$prog – Generate and manage GPG keys

Usage:
  $prog <command> [options]

Commands:
  generate, gen    Generate a new GPG key pair
  list, ls         List existing GPG keys
  export           Export a public key (ASCII armor)
  delete, del      Delete a GPG key
  backup           Backup all GPG keys (public + secret + ownertrust)
  import           Import keys from a backup file or directory
  github, gh       GitHub integration (add/config/setup/list/remove)
  help, -h         Show this help message

Generate options:
  --name NAME      Real name (skips interactive prompt)
  --email EMAIL    Email address (skips interactive prompt)
  --algo ALGO      Algorithm: ed25519 (default) or rsa4096
  --expire TIME    Expiration: 1y (default), 6m, 2y, 0 (never)
  --no-sign        Skip git signing configuration
  --no-github      Skip GitHub integration prompt

List options:
  --secret         List secret keys instead of public keys

Export options:
  --clipboard      Copy to clipboard instead of stdout
  -o FILE          Write to file

Delete options:
  --force          Skip confirmation prompt
  --public-only    Only delete the public key

Backup options:
  --dir DIR        Backup directory (default: ~/gpg-backup/)

Import options:
  --dir DIR        Import all files from a directory

GitHub subcommands:
  github add       Add GPG key to GitHub account (requires gh CLI)
  github config    Configure git for GPG signing
  github setup     Add to GitHub + configure git (add + config)
  github list      List GPG keys on GitHub account
  github remove    Remove a GPG key from GitHub

Examples:
  $prog generate
  $prog generate --name "John Doe" --email john@example.com --algo ed25519
  $prog list
  $prog export --clipboard
  $prog export user@example.com -o key.asc
  $prog delete
  $prog backup --dir ~/my-backup/
  $prog import ~/backup/gpg-public-keys.asc
  $prog import --dir ~/backup/
  $prog github setup
EOF
  exit 0
}

# ── Commands ──

cmd_generate() {
  name=""
  email=""
  algo="ed25519"
  expire="1y"
  no_sign=false
  no_github=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --name)   name="$2"; shift 2 ;;
      --email)  email="$2"; shift 2 ;;
      --algo)   algo="$2"; shift 2 ;;
      --expire) expire="$2"; shift 2 ;;
      --no-sign)   no_sign=true; shift ;;
      --no-github) no_github=true; shift ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  printf "\n${BLUE}🔐 GPG Key Generation${RESET}\n\n"

  # Interactive prompts for missing values
  if [ -z "$name" ]; then
    default_name=$(git config --global user.name 2>/dev/null || true)
    if [ -n "$default_name" ]; then
      printf "  Real name [%s]: " "$default_name"
    else
      printf "  Real name: "
    fi
    read -r name
    if [ -z "$name" ] && [ -n "$default_name" ]; then
      name="$default_name"
    fi
    [ -n "$name" ] || die "Name is required."
  fi

  if [ -z "$email" ]; then
    default_email=$(git config --global user.email 2>/dev/null || true)
    if [ -n "$default_email" ]; then
      printf "  Email [%s]: " "$default_email"
    else
      printf "  Email: "
    fi
    read -r email
    if [ -z "$email" ] && [ -n "$default_email" ]; then
      email="$default_email"
    fi
    [ -n "$email" ] || die "Email is required."
  fi

  # Algorithm selection (interactive only if not provided)
  if [ "$algo" = "ed25519" ] && [ $# -eq 0 ] 2>/dev/null; then
    : # keep default, already set above
  fi
  case "$algo" in
    ed25519|rsa4096) ;;
    *) die "Unsupported algorithm: $algo. Use 'ed25519' or 'rsa4096'." ;;
  esac

  # Build gpg batch parameter file
  param_file=$(mktemp)
  register_tmp "$param_file"

  if [ "$algo" = "ed25519" ]; then
    cat > "$param_file" <<EOF
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Key-Usage: sign
Subkey-Type: ecdh
Subkey-Curve: cv25519
Subkey-Usage: encrypt
Name-Real: $name
Name-Email: $email
Expire-Date: $expire
EOF
  else
    cat > "$param_file" <<EOF
%no-protection
Key-Type: rsa
Key-Length: 4096
Key-Usage: sign
Subkey-Type: rsa
Subkey-Length: 4096
Subkey-Usage: encrypt
Name-Real: $name
Name-Email: $email
Expire-Date: $expire
EOF
  fi

  printf "\n  Generating %s key...\n" "$algo"

  output=$(gpg --batch --generate-key "$param_file" 2>&1) || die "Key generation failed: $output"

  # Retrieve the new key info
  keyid=$(gpg --list-secret-keys --with-colons --keyid-format long "$email" 2>/dev/null \
    | awk -F: '/^sec:/ { print $5; exit }')
  fingerprint=$(gpg --fingerprint --keyid-format long "$email" 2>/dev/null \
    | awk '/Key fingerprint/ { sub(/.*= /, ""); print; exit }')
  expires_ts=$(gpg --list-secret-keys --with-colons --keyid-format long "$email" 2>/dev/null \
    | awk -F: '/^sec:/ { print $7; exit }')

  if [ -n "$expires_ts" ] && [ "$expires_ts" != "0" ] && [ -n "$expires_ts" ]; then
    expires_fmt=$(date -d "@$expires_ts" "+%Y-%m-%d" 2>/dev/null || printf "%s" "$expires_ts")
  else
    expires_fmt="never"
  fi

  printf "\n"
  success "Key generated"
  printf "     Key ID:      %s\n" "$keyid"
  printf "     Fingerprint: %s\n" "$fingerprint"
  printf "     Expires:     %s\n" "$expires_fmt"

  # Prompt to set passphrase
  printf "\n"
  if confirm "  Set a passphrase on this key? (recommended)"; then
    gpg --passwd "$keyid" 2>/dev/null || warn "Could not set passphrase. You can set it later with: gpg --passwd $keyid"
  fi

  # Git signing configuration
  if [ "$no_sign" = false ]; then
    printf "\n"
    if confirm "  Configure git signing?"; then
      github_config_with_key "$keyid"
    fi
  fi

  # GitHub integration
  if [ "$no_github" = false ]; then
    printf "\n"
    if confirm "  Add to GitHub?"; then
      github_add_with_key "$keyid"
    fi
  fi

  printf "\n"
}

cmd_list() {
  secret_flag=""
  list_cmd="--list-keys"

  while [ $# -gt 0 ]; do
    case "$1" in
      --secret) list_cmd="--list-secret-keys"; shift ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  gpg $list_cmd --keyid-format long 2>/dev/null || printf "No keys found.\n"
}

cmd_export() {
  identifier=""
  clipboard=false
  outfile=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --clipboard) clipboard=true; shift ;;
      -o)          outfile="$2"; shift 2 ;;
      *)           identifier="$1"; shift ;;
    esac
  done

  if [ -n "$identifier" ]; then
    keyid="$identifier"
  else
    keyid=$(select_key --public)
  fi

  if [ "$clipboard" = true ]; then
    gpg --armor --export "$keyid" | copy_to_clipboard
    success "Public key copied to clipboard."
  elif [ -n "$outfile" ]; then
    gpg --armor --export "$keyid" > "$outfile"
    success "Public key written to $outfile"
  else
    gpg --armor --export "$keyid"
  fi
}

cmd_delete() {
  identifier=""
  force=false
  public_only=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --force)       force=true; shift ;;
      --public-only) public_only=true; shift ;;
      *)             identifier="$1"; shift ;;
    esac
  done

  if [ -n "$identifier" ]; then
    keyid="$identifier"
  else
    if [ "$public_only" = true ]; then
      keyid=$(select_key --public)
    else
      keyid=$(select_key)
    fi
  fi

  # Show key info before deletion
  printf "\n${BLUE}Key to delete:${RESET}\n"
  gpg --list-keys --keyid-format long "$keyid" 2>/dev/null || true
  printf "\n"

  if [ "$force" = false ]; then
    confirm "Delete this key?" || { printf "Aborted.\n"; return 0; }
  fi

  if [ "$public_only" = true ]; then
    gpg --batch --yes --delete-keys "$keyid" 2>/dev/null
    success "Public key $keyid deleted."
  else
    gpg --batch --yes --delete-secret-and-public-key "$keyid" 2>/dev/null
    success "Key $keyid deleted (secret + public)."
  fi
}

cmd_backup() {
  backup_dir="$HOME/gpg-backup"

  while [ $# -gt 0 ]; do
    case "$1" in
      --dir) backup_dir="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  mkdir -p "$backup_dir"
  date_stamp=$(date "+%Y%m%d")

  pub_file="$backup_dir/gpg-public-keys-${date_stamp}.asc"
  sec_file="$backup_dir/gpg-secret-keys-${date_stamp}.asc"
  trust_file="$backup_dir/gpg-ownertrust-${date_stamp}.txt"

  gpg --armor --export > "$pub_file"
  printf "📦 %s\n" "$pub_file"

  gpg --armor --export-secret-keys > "$sec_file"
  printf "📦 %s\n" "$sec_file"

  gpg --export-ownertrust > "$trust_file"
  printf "📦 %s\n" "$trust_file"

  printf "\n"
  success "Backup complete in $backup_dir"
  warn "The secret key file contains your private keys. Store it securely."
}

cmd_import() {
  import_dir=""
  files=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --dir) import_dir="$2"; shift 2 ;;
      *)     files="$files $1"; shift ;;
    esac
  done

  if [ -n "$import_dir" ]; then
    if [ ! -d "$import_dir" ]; then
      die "Directory not found: $import_dir"
    fi
    for f in "$import_dir"/*; do
      [ -f "$f" ] || continue
      import_file "$f"
    done
  elif [ -n "$files" ]; then
    for f in $files; do
      [ -f "$f" ] || die "File not found: $f"
      import_file "$f"
    done
  else
    die "Provide a file path or --dir to import from."
  fi

  printf "\n"
  success "Import complete."
}

import_file() {
  file="$1"
  filename=$(basename "$file")

  # Detect type by file content headers
  if grep -q "BEGIN PGP PUBLIC KEY BLOCK" "$file" 2>/dev/null; then
    info "Importing public keys from $filename..."
    gpg --import "$file" 2>&1
  elif grep -q "BEGIN PGP PRIVATE KEY BLOCK" "$file" 2>/dev/null; then
    info "Importing secret keys from $filename..."
    gpg --import "$file" 2>&1
  elif echo "$filename" | grep -q "ownertrust"; then
    info "Importing ownertrust from $filename..."
    gpg --import-ownertrust "$file" 2>&1
  else
    warn "Skipping unknown file: $filename"
  fi
}

# ── GitHub integration ──

github_check_gh() {
  command -v gh >/dev/null 2>&1 || die "'gh' CLI is required for GitHub integration. Install it from https://cli.github.com/"
  gh auth status >/dev/null 2>&1 || die "Not authenticated with GitHub. Run 'gh auth login' first."
}

github_add_with_key() {
  keyid="$1"
  github_check_gh
  tmpkey=$(mktemp)
  register_tmp "$tmpkey"
  gpg --armor --export "$keyid" > "$tmpkey"
  gh gpg-key add "$tmpkey" 2>&1
  success "GPG key added to GitHub."
}

github_config_with_key() {
  keyid="$1"
  if ! command -v git >/dev/null 2>&1; then
    warn "git is not installed. Cannot configure git signing."
    return 1
  fi
  git config --global user.signingkey "$keyid"
  git config --global commit.gpgsign true
  git config --global gpg.program gpg
  success "Git configured for GPG signing (key: $keyid)."
}

cmd_github() {
  if [ $# -lt 1 ]; then
    printf "Usage: %s github <add|config|setup|list|remove>\n" "$(basename "$0")"
    return 1
  fi

  action="$1"
  shift

  case "$action" in
    add)
      github_check_gh
      keyid=$(select_key "$@")
      github_add_with_key "$keyid"
      ;;
    config)
      keyid=$(select_key "$@")
      github_config_with_key "$keyid"
      ;;
    setup)
      github_check_gh
      keyid=$(select_key "$@")
      github_add_with_key "$keyid"
      github_config_with_key "$keyid"
      ;;
    list)
      github_check_gh
      gh gpg-key list
      ;;
    remove)
      github_check_gh
      printf "\n${BLUE}GPG keys on GitHub:${RESET}\n"
      gh gpg-key list
      printf "\nEnter the GPG key ID to remove: "
      read -r remove_id
      [ -n "$remove_id" ] || die "No key ID provided."
      if confirm "Remove key $remove_id from GitHub?"; then
        gh gpg-key delete "$remove_id" --yes 2>&1
        success "GPG key removed from GitHub."
      else
        printf "Aborted.\n"
      fi
      ;;
    *)
      die "Unknown github action: $action. Use add/config/setup/list/remove."
      ;;
  esac
}

# ── Main dispatch ──

check_dep gpg

if [ $# -lt 1 ]; then
  show_help
fi

cmd="$1"
shift

case "$cmd" in
  generate|gen) cmd_generate "$@" ;;
  list|ls)      cmd_list "$@" ;;
  export)       cmd_export "$@" ;;
  delete|del)   cmd_delete "$@" ;;
  backup)       cmd_backup "$@" ;;
  import)       cmd_import "$@" ;;
  github|gh)    cmd_github "$@" ;;
  help|-h|--help) show_help ;;
  --version)    printf '%s\n' "$VERSION"; exit 0 ;;
  *)
    printf "Unknown command: %s\n\n" "$cmd"
    show_help
    ;;
esac
