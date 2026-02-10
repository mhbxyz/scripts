#!/bin/sh

# Script to generate and manage SSH keys
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

# ── SSH constants ──

SSH_DIR="$HOME/.ssh"
SSH_CONFIG="$SSH_DIR/config"
EDITOR="${EDITOR:-nano}"

# ── SSH helpers ──

ensure_ssh_dir() {
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
}

ensure_ssh_config() {
  ensure_ssh_dir
  if [ ! -f "$SSH_CONFIG" ]; then
    touch "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
  fi
}

# ── Config functions ──

config_add_host() {
  host="$1"
  hostname="$2"
  user="$3"
  identity_file="${4:-}"

  ensure_ssh_config

  if grep -q "^Host[[:space:]]\+$host\$" "$SSH_CONFIG"; then
    die "Host '$host' already exists in config."
  fi

  {
    printf "\n"
    printf "Host %s\n" "$host"
    printf "    HostName %s\n" "$hostname"
    printf "    User %s\n" "$user"
    if [ -n "$identity_file" ]; then
      printf "    IdentityFile %s\n" "$identity_file"
    fi
  } >> "$SSH_CONFIG"

  success "Added host '$host'."
}

config_remove_host() {
  host="$1"
  ensure_ssh_config

  if ! grep -q "^Host[[:space:]]\+$host\$" "$SSH_CONFIG"; then
    die "Host '$host' not found."
  fi

  tmpfile=$(mktemp)
  register_tmp "$tmpfile"

  awk -v h="$host" '
    BEGIN { skip=0 }
    /^Host / {
      if ($2 == h) { skip=1; next }
      if (skip) { skip=0 }
    }
    skip==0 { print }
  ' "$SSH_CONFIG" > "$tmpfile"

  cp "$SSH_CONFIG" "$SSH_CONFIG.bak"
  mv "$tmpfile" "$SSH_CONFIG"

  success "Removed host '$host'. Backup saved to $SSH_CONFIG.bak"
}

config_list_hosts() {
  ensure_ssh_config
  awk '/^Host / {print $2}' "$SSH_CONFIG"
}

config_show_host() {
  host="$1"
  ensure_ssh_config
  awk -v h="$host" '
    BEGIN { p=0 }
    /^Host / {
      if ($2 == h) { print; p=1; next }
      if (p==1) { exit }
    }
    p==1 { print }
  ' "$SSH_CONFIG"
}

config_edit_host() {
  host="$1"
  ensure_ssh_config

  if ! grep -q "^Host[[:space:]]\+$host\$" "$SSH_CONFIG"; then
    die "Host '$host' not found."
  fi

  temp_file=$(mktemp)
  register_tmp "$temp_file"

  awk -v h="$host" '
    BEGIN { p=0 }
    /^Host / {
      if ($2 == h) { print; p=1; next }
      if (p==1) { exit }
    }
    p==1 { print }
  ' "$SSH_CONFIG" > "$temp_file"

  $EDITOR "$temp_file"

  tmpfile=$(mktemp)
  register_tmp "$tmpfile"

  awk -v h="$host" '
    BEGIN { skip=0 }
    /^Host / {
      if ($2 == h) { skip=1; next }
      if (skip) { skip=0 }
    }
    skip==0 { print }
  ' "$SSH_CONFIG" > "$tmpfile"

  cp "$SSH_CONFIG" "$SSH_CONFIG.bak"
  mv "$tmpfile" "$SSH_CONFIG"

  printf "\n" >> "$SSH_CONFIG"
  cat "$temp_file" >> "$SSH_CONFIG"

  success "Host '$host' updated. Backup saved to $SSH_CONFIG.bak"
}

config_backup() {
  ensure_ssh_config
  cp "$SSH_CONFIG" "$SSH_CONFIG.bak"
  success "Backup saved to $SSH_CONFIG.bak"
}

# ── GitHub integration ──

github_check_gh() {
  command -v gh >/dev/null 2>&1 || die "'gh' CLI is required for GitHub integration. Install it from https://cli.github.com/"
  gh auth status >/dev/null 2>&1 || die "Not authenticated with GitHub. Run 'gh auth login' first."
}

github_add_key() {
  key_file="$1"
  title="${2:-SSH key}"

  if [ ! -f "$key_file" ]; then
    die "Key file not found: $key_file"
  fi

  gh ssh-key add "$key_file" --title "$title" 2>&1
  success "SSH key added to GitHub."
}

# ── Select key file interactively ──

select_key_file() {
  ensure_ssh_dir

  tmpkeys=$(mktemp)
  register_tmp "$tmpkeys"

  # Find all .pub files
  count=0
  for pub in "$SSH_DIR"/*.pub; do
    [ -f "$pub" ] || continue
    printf "%s\n" "$pub" >> "$tmpkeys"
    count=$((count + 1))
  done

  if [ "$count" -eq 0 ]; then
    die "No SSH keys found in $SSH_DIR. Run '$(basename "$0") generate' first."
  fi

  if [ "$count" -eq 1 ]; then
    cat "$tmpkeys"
    return 0
  fi

  printf "\n${BLUE}Available SSH keys:${RESET}\n"
  i=1
  while IFS= read -r pub; do
    fingerprint=$(ssh-keygen -l -f "$pub" 2>/dev/null | awk '{print $2}')
    comment=$(ssh-keygen -l -f "$pub" 2>/dev/null | sed 's/.* //')
    printf "  %d) %s  %s  %s\n" "$i" "$(basename "$pub")" "$fingerprint" "$comment"
    i=$((i + 1))
  done < "$tmpkeys"

  printf "\nSelect key [1-%d]: " "$count"
  read -r choice
  if [ -z "$choice" ] || [ "$choice" -lt 1 ] 2>/dev/null || [ "$choice" -gt "$count" ] 2>/dev/null; then
    die "Invalid selection."
  fi

  awk "NR==$choice" "$tmpkeys"
}

# ── Help ──

show_help() {
  prog=$(basename "$0")
  cat <<EOF
$prog – Generate and manage SSH keys

Usage:
  $prog <command> [options]

Commands:
  generate, gen    Generate a new SSH key pair
  list, ls         List SSH keys in ~/.ssh
  delete, del      Delete an SSH key pair
  config, cfg      Manage ~/.ssh/config (add/remove/list/show/edit/backup)
  github, gh       GitHub integration (add/list/remove)
  help, -h         Show this help message

Generate options:
  --email EMAIL        Email/comment for the key
  --name NAME          Key filename (default: id_ed25519)
  --type TYPE          Key type: ed25519 (default) or rsa
  --comment TEXT       Additional comment
  --host HOST          Hostname for SSH config block
  --alias ALIAS        SSH config alias (default: same as host)
  --agent              Add key to ssh-agent
  --no-clipboard       Don't copy public key to clipboard
  --no-config          Skip config block even with --host
  --no-passphrase      Generate key without passphrase (non-interactive)
  --no-github          Skip GitHub integration prompt

Config subcommands:
  config add <host> <hostname> <user> [--identity FILE]
  config remove <host> [--force]
  config list
  config show <host>
  config edit <host>
  config backup

GitHub subcommands:
  github add [key_file]    Add an SSH public key to GitHub (default: interactive)
  github list              List SSH keys on GitHub account
  github remove            Remove an SSH key from GitHub

Examples:
  $prog generate --email user@example.com --name id_github
  $prog generate --email user@example.com --host github.com --alias github
  $prog list
  $prog delete id_github
  $prog config add myserver example.com user1 --identity ~/.ssh/id_rsa
  $prog config list
  $prog github add ~/.ssh/id_ed25519.pub
  $prog github list
EOF
  exit 0
}

# ── Commands ──

cmd_generate() {
  email=""
  key_name="id_ed25519"
  key_type="ed25519"
  comment=""
  ssh_host=""
  ssh_alias=""
  add_agent=false
  do_clipboard=true
  do_config=true
  no_passphrase=false
  no_github=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --email)        email="$2"; shift 2 ;;
      --name)         key_name="$2"; shift 2 ;;
      --type)         key_type="$2"; shift 2 ;;
      --comment)      comment="$2"; shift 2 ;;
      --host)         ssh_host="$2"; shift 2 ;;
      --alias)        ssh_alias="$2"; shift 2 ;;
      --agent)        add_agent=true; shift ;;
      --no-clipboard) do_clipboard=false; shift ;;
      --no-config)    do_config=false; shift ;;
      --no-passphrase) no_passphrase=true; shift ;;
      --no-github)    no_github=true; shift ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  # Interactive prompt for email if not provided
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

  case "$key_type" in
    ed25519|rsa) ;;
    *) die "Unsupported key type: $key_type. Use 'ed25519' or 'rsa'." ;;
  esac

  ensure_ssh_dir

  key_path="$SSH_DIR/$key_name"
  full_comment="$email"
  if [ -n "$comment" ]; then
    full_comment="$email ($comment)"
  fi

  info "Generating $key_type key at $key_path..."

  passphrase_args=""
  if [ "$no_passphrase" = true ]; then
    passphrase_args="-N \"\""
  fi

  if [ "$key_type" = "rsa" ]; then
    if [ "$no_passphrase" = true ]; then
      ssh-keygen -t rsa -b 4096 -C "$full_comment" -f "$key_path" -N ""
    else
      ssh-keygen -t rsa -b 4096 -C "$full_comment" -f "$key_path"
    fi
  else
    if [ "$no_passphrase" = true ]; then
      ssh-keygen -t "$key_type" -C "$full_comment" -f "$key_path" -N ""
    else
      ssh-keygen -t "$key_type" -C "$full_comment" -f "$key_path"
    fi
  fi

  success "Key generated."
  printf "  Private key: %s\n" "$key_path"
  printf "  Public key:  %s.pub\n" "$key_path"
  printf "  Comment:     %s\n" "$full_comment"

  # Add to ssh-agent
  if [ "$add_agent" = true ]; then
    if ssh-add "$key_path" 2>/dev/null; then
      success "Key added to ssh-agent."
    else
      warn "Could not add key to agent. You may need to run: eval \$(ssh-agent) && ssh-add $key_path"
    fi
  fi

  # Copy to clipboard
  if [ "$do_clipboard" = true ]; then
    if copy_to_clipboard < "$key_path.pub"; then
      success "Public key copied to clipboard."
    fi
  fi

  # Add SSH config block
  if [ -n "$ssh_host" ] && [ "$do_config" = true ]; then
    if [ -z "$ssh_alias" ]; then
      ssh_alias="$ssh_host"
    fi
    ensure_ssh_config
    if ! grep -q "^Host[[:space:]]\+$ssh_alias\$" "$SSH_CONFIG" 2>/dev/null; then
      {
        printf "\n"
        printf "Host %s\n" "$ssh_alias"
        printf "    HostName %s\n" "$ssh_host"
        printf "    User git\n"
        printf "    IdentityFile %s\n" "$key_path"
        printf "    IdentitiesOnly yes\n"
      } >> "$SSH_CONFIG"
      success "SSH config updated with alias '$ssh_alias'."
    else
      warn "SSH config already contains a block for '$ssh_alias'. Skipped."
    fi
  fi

  # GitHub integration
  if [ "$no_github" = false ]; then
    printf "\n"
    if confirm "  Add to GitHub?"; then
      github_check_gh
      github_add_key "$key_path.pub" "$full_comment"
    fi
  fi

  printf "\n"
}

cmd_list() {
  ensure_ssh_dir

  found=false
  for pub in "$SSH_DIR"/*.pub; do
    [ -f "$pub" ] || continue
    found=true
    ssh-keygen -l -f "$pub" 2>/dev/null
  done

  if [ "$found" = false ]; then
    info "No SSH keys found in $SSH_DIR."
  fi
}

cmd_delete() {
  force=false
  key_name=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --force) force=true; shift ;;
      *)       key_name="$1"; shift ;;
    esac
  done

  if [ -z "$key_name" ]; then
    die "Usage: $(basename "$0") delete <key_name> [--force]"
  fi

  key_path="$SSH_DIR/$key_name"

  if [ ! -f "$key_path" ] && [ ! -f "$key_path.pub" ]; then
    die "Key '$key_name' not found in $SSH_DIR."
  fi

  # Show key info
  if [ -f "$key_path.pub" ]; then
    printf "\n${BLUE}Key to delete:${RESET}\n"
    ssh-keygen -l -f "$key_path.pub" 2>/dev/null || true
    printf "\n"
  fi

  if [ "$force" = false ]; then
    confirm "Delete this key?" || { printf "Aborted.\n"; return 0; }
  fi

  rm -f "$key_path" "$key_path.pub"
  success "Key '$key_name' deleted."
}

cmd_config() {
  if [ $# -lt 1 ]; then
    printf "Usage: %s config <add|remove|list|show|edit|backup>\n" "$(basename "$0")"
    return 1
  fi

  action="$1"
  shift

  case "$action" in
    add)
      host=""
      hostname=""
      user=""
      identity=""

      # Parse positional args then flags
      positional=0
      while [ $# -gt 0 ]; do
        case "$1" in
          --identity) identity="$2"; shift 2 ;;
          --force)    shift ;; # ignored for add
          *)
            positional=$((positional + 1))
            case "$positional" in
              1) host="$1" ;;
              2) hostname="$1" ;;
              3) user="$1" ;;
            esac
            shift
            ;;
        esac
      done

      [ -n "$host" ] && [ -n "$hostname" ] && [ -n "$user" ] || \
        die "Usage: $(basename "$0") config add <host> <hostname> <user> [--identity FILE]"

      config_add_host "$host" "$hostname" "$user" "$identity"
      ;;
    remove)
      force=false
      host=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --force) force=true; shift ;;
          *)       host="$1"; shift ;;
        esac
      done

      [ -n "$host" ] || die "Usage: $(basename "$0") config remove <host> [--force]"

      if [ "$force" = false ]; then
        config_show_host "$host"
        confirm "Remove this host?" || { printf "Aborted.\n"; return 0; }
      fi
      config_remove_host "$host"
      ;;
    list)
      config_list_hosts
      ;;
    show)
      [ $# -ge 1 ] || die "Usage: $(basename "$0") config show <host>"
      config_show_host "$1"
      ;;
    edit)
      [ $# -ge 1 ] || die "Usage: $(basename "$0") config edit <host>"
      config_edit_host "$1"
      ;;
    backup)
      config_backup
      ;;
    *)
      die "Unknown config action: $action. Use add/remove/list/show/edit/backup."
      ;;
  esac
}

cmd_github() {
  if [ $# -lt 1 ]; then
    printf "Usage: %s github <add|list|remove>\n" "$(basename "$0")"
    return 1
  fi

  action="$1"
  shift

  case "$action" in
    add)
      github_check_gh
      if [ $# -ge 1 ]; then
        key_file="$1"
      else
        key_file=$(select_key_file)
      fi
      title=$(ssh-keygen -l -f "$key_file" 2>/dev/null | sed 's/.* //' || basename "$key_file")
      github_add_key "$key_file" "$title"
      ;;
    list)
      github_check_gh
      gh ssh-key list
      ;;
    remove)
      github_check_gh
      printf "\n${BLUE}SSH keys on GitHub:${RESET}\n"
      gh ssh-key list
      printf "\nEnter the SSH key ID to remove: "
      read -r remove_id
      [ -n "$remove_id" ] || die "No key ID provided."
      if confirm "Remove key $remove_id from GitHub?"; then
        gh ssh-key delete "$remove_id" --yes 2>&1
        success "SSH key removed from GitHub."
      else
        printf "Aborted.\n"
      fi
      ;;
    *)
      die "Unknown github action: $action. Use add/list/remove."
      ;;
  esac
}

# ── Main dispatch ──

check_dep ssh-keygen

if [ $# -lt 1 ]; then
  show_help
fi

cmd="$1"
shift

case "$cmd" in
  generate|gen) cmd_generate "$@" ;;
  list|ls)      cmd_list "$@" ;;
  delete|del)   cmd_delete "$@" ;;
  config|cfg)   cmd_config "$@" ;;
  github|gh)    cmd_github "$@" ;;
  help|-h|--help) show_help ;;
  --version)    printf '%s\n' "$VERSION"; exit 0 ;;
  *)
    printf "Unknown command: %s\n\n" "$cmd"
    show_help
    ;;
esac
