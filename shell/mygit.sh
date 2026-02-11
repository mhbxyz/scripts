#!/bin/sh

# Simplified git config management
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

# ── Scope helper ──

parse_scope() {
  _scope="--global"
  while [ $# -gt 0 ]; do
    case "$1" in
      --global) _scope="--global"; shift ;;
      --local)  _scope="--local"; shift ;;
      --system) _scope="--system"; shift ;;
      *) break ;;
    esac
  done
  printf '%s' "$_scope"
}

git_get() {
  git config "$@" 2>/dev/null || true
}

# ── show ──

cmd_show() {
  _scope="--global"
  _all=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --global) _scope="--global"; shift ;;
      --local)  _scope="--local"; shift ;;
      --system) _scope="--system"; shift ;;
      --all)    _all=true; shift ;;
      *) die "Unknown option: '$1'" ;;
    esac
  done

  if [ "$_all" = true ]; then
    git config $_scope --list 2>/dev/null || info "No configuration found."
    return
  fi

  _scope_label=$(printf '%s' "$_scope" | sed 's/^--//')

  _name=$(git_get $_scope user.name)
  _email=$(git_get $_scope user.email)
  _editor=$(git_get $_scope core.editor)
  _gpgsign=$(git_get $_scope commit.gpgsign)
  _sigkey=$(git_get $_scope user.signingkey)
  _gpgfmt=$(git_get $_scope gpg.format)
  _cred=$(git_get $_scope credential.helper)
  _defbranch=$(git_get $_scope init.defaultBranch)
  _pullrebase=$(git_get $_scope pull.rebase)

  printf "Git configuration (%s):\n" "$_scope_label"

  if [ -n "$_name" ] || [ -n "$_email" ]; then
    printf "  User:           %s" "${_name:-<not set>}"
    [ -n "$_email" ] && printf " <%s>" "$_email"
    printf "\n"
  else
    printf "  User:           <not set>\n"
  fi

  printf "  Editor:         %s\n" "${_editor:-<not set>}"

  if [ "$_gpgsign" = "true" ]; then
    _fmt="${_gpgfmt:-gpg}"
    printf "  Signing:        %s (key: %s)\n" "$(printf '%s' "$_fmt" | tr '[:lower:]' '[:upper:]')" "${_sigkey:-<not set>}"
  else
    printf "  Signing:        off\n"
  fi

  printf "  Credentials:    %s\n" "${_cred:-<not set>}"
  printf "  Default branch: %s\n" "${_defbranch:-<not set>}"
  printf "  Pull strategy:  %s\n" "${_pullrebase:-<not set>}"
}

# ── user ──

cmd_user() {
  _scope="--global"
  _name="" _email=""
  _set_name=false _set_email=false
  _positional=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --global) _scope="--global"; shift ;;
      --local)  _scope="--local"; shift ;;
      --name)
        [ $# -ge 2 ] || die "--name requires an argument"
        _name="$2"; _set_name=true; shift 2 ;;
      --email)
        [ $# -ge 2 ] || die "--email requires an argument"
        _email="$2"; _set_email=true; shift 2 ;;
      -*)  die "Unknown option: '$1'" ;;
      *)   _positional="$_positional $1"; shift ;;
    esac
  done

  # Handle positional args: mygit user "Name" email
  _positional=$(printf '%s' "$_positional" | sed 's/^ //')
  if [ -n "$_positional" ] && [ "$_set_name" = false ] && [ "$_set_email" = false ]; then
    _name=$(printf '%s' "$_positional" | sed 's/ [^ ]*$//')
    _email=$(printf '%s' "$_positional" | awk '{print $NF}')
    # If name and email are the same, it means only one arg — treat as name
    if [ "$_name" = "$_email" ]; then
      # Check if it looks like an email
      case "$_name" in
        *@*) _set_email=true; _set_name=false; _email="$_name"; _name="" ;;
        *)   _set_name=true; _set_email=false; _email="" ;;
      esac
    else
      _set_name=true
      _set_email=true
    fi
  fi

  # If no args at all, interactive mode
  if [ "$_set_name" = false ] && [ "$_set_email" = false ] && [ -z "$_positional" ]; then
    _cur_name=$(git_get $_scope user.name)
    _cur_email=$(git_get $_scope user.email)
    printf "Name [%s]: " "${_cur_name:-}"
    read -r _name </dev/tty
    [ -z "$_name" ] && _name="$_cur_name"
    printf "Email [%s]: " "${_cur_email:-}"
    read -r _email </dev/tty
    [ -z "$_email" ] && _email="$_cur_email"
    _set_name=true
    _set_email=true
  fi

  if [ "$_set_name" = true ] && [ -n "$_name" ]; then
    git config $_scope user.name "$_name"
    success "Set user.name = $_name"
  fi
  if [ "$_set_email" = true ] && [ -n "$_email" ]; then
    git config $_scope user.email "$_email"
    success "Set user.email = $_email"
  fi
}

# ── editor ──

cmd_editor() {
  _scope="--global"

  while [ $# -gt 0 ]; do
    case "$1" in
      --global) _scope="--global"; shift ;;
      --local)  _scope="--local"; shift ;;
      -*) die "Unknown option: '$1'" ;;
      *)  break ;;
    esac
  done

  if [ $# -gt 0 ]; then
    _editor="$*"
    git config $_scope core.editor "$_editor"
    success "Set core.editor = $_editor"
    return
  fi

  # Interactive mode
  printf "Select editor:\n"
  printf "  1) vim\n"
  printf "  2) nvim\n"
  printf "  3) nano\n"
  printf "  4) code --wait\n"
  printf "  5) emacs\n"
  printf "  6) helix\n"
  printf "  7) other\n"
  printf "Choice [1-7]: "
  read -r _choice </dev/tty

  case "$_choice" in
    1) _editor="vim" ;;
    2) _editor="nvim" ;;
    3) _editor="nano" ;;
    4) _editor="code --wait" ;;
    5) _editor="emacs" ;;
    6) _editor="helix" ;;
    7)
      printf "Enter editor command: "
      read -r _editor </dev/tty
      [ -z "$_editor" ] && die "No editor specified"
      ;;
    *) die "Invalid choice: '$_choice'" ;;
  esac

  git config $_scope core.editor "$_editor"
  success "Set core.editor = $_editor"
}

# ── credentials ──

cmd_credentials() {
  _scope="--global"
  _timeout=3600
  _helper=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --global)  _scope="--global"; shift ;;
      --local)   _scope="--local"; shift ;;
      --timeout)
        [ $# -ge 2 ] || die "--timeout requires an argument"
        _timeout="$2"; shift 2 ;;
      -*) die "Unknown option: '$1'" ;;
      *)  [ -z "$_helper" ] && _helper="$1"; shift ;;
    esac
  done

  if [ -n "$_helper" ]; then
    case "$_helper" in
      store)
        git config $_scope credential.helper store
        success "Set credential.helper = store"
        ;;
      cache)
        git config $_scope credential.helper "cache --timeout=$_timeout"
        success "Set credential.helper = cache --timeout=$_timeout"
        ;;
      osxkeychain)
        git config $_scope credential.helper osxkeychain
        success "Set credential.helper = osxkeychain"
        ;;
      *)
        git config $_scope credential.helper "$_helper"
        success "Set credential.helper = $_helper"
        ;;
    esac
    return
  fi

  # Interactive mode — platform detection
  _platform=$(uname -s)
  printf "Select credential helper:\n"
  printf "  1) store (plain-text file)\n"
  printf "  2) cache (in-memory, timeout)\n"
  case "$_platform" in
    Darwin) printf "  3) osxkeychain (macOS Keychain)\n" ;;
  esac
  printf "Choice: "
  read -r _choice </dev/tty

  case "$_choice" in
    1) git config $_scope credential.helper store
       success "Set credential.helper = store" ;;
    2) printf "Timeout in seconds [3600]: "
       read -r _t </dev/tty
       [ -z "$_t" ] && _t=3600
       git config $_scope credential.helper "cache --timeout=$_t"
       success "Set credential.helper = cache --timeout=$_t" ;;
    3)
      case "$_platform" in
        Darwin)
          git config $_scope credential.helper osxkeychain
          success "Set credential.helper = osxkeychain" ;;
        *) die "Invalid choice: '$_choice'" ;;
      esac ;;
    *) die "Invalid choice: '$_choice'" ;;
  esac
}

# ── signing ──

cmd_signing() {
  _scope="--global"

  while [ $# -gt 0 ]; do
    case "$1" in
      --global) _scope="--global"; shift ;;
      --local)  _scope="--local"; shift ;;
      -*) die "Unknown option: '$1'" ;;
      *)  break ;;
    esac
  done

  if [ $# -eq 0 ]; then
    # Show current signing status
    _gpgsign=$(git_get $_scope commit.gpgsign)
    _sigkey=$(git_get $_scope user.signingkey)
    _gpgfmt=$(git_get $_scope gpg.format)
    if [ "$_gpgsign" = "true" ]; then
      _fmt="${_gpgfmt:-gpg}"
      info "Signing: $(printf '%s' "$_fmt" | tr '[:lower:]' '[:upper:]') (key: ${_sigkey:-<not set>})"
    else
      info "Signing: off"
    fi
    return
  fi

  _mode="$1"; shift

  case "$_mode" in
    gpg)
      [ $# -ge 1 ] || die "Usage: mygit signing gpg <key-id>"
      _keyid="$1"
      git config $_scope commit.gpgsign true
      git config $_scope user.signingkey "$_keyid"
      git config $_scope gpg.format openpgp
      success "Configured GPG signing (key: $_keyid)"
      ;;
    ssh)
      [ $# -ge 1 ] || die "Usage: mygit signing ssh <key-file>"
      _keyfile="$1"
      git config $_scope commit.gpgsign true
      git config $_scope user.signingkey "$_keyfile"
      git config $_scope gpg.format ssh
      success "Configured SSH signing (key: $_keyfile)"
      ;;
    off)
      git config $_scope commit.gpgsign false
      success "Disabled commit signing"
      ;;
    *)
      die "Unknown signing mode: '$_mode'. Use gpg, ssh, or off."
      ;;
  esac
}

# ── aliases ──

cmd_aliases() {
  _scope="--global"

  while [ $# -gt 0 ]; do
    case "$1" in
      --global) _scope="--global"; shift ;;
      --local)  _scope="--local"; shift ;;
      -*) die "Unknown option: '$1'" ;;
      *)  break ;;
    esac
  done

  if [ $# -eq 0 ]; then
    die "Usage: mygit aliases <list|add|remove|defaults>"
  fi

  _subcmd="$1"; shift

  case "$_subcmd" in
    list|ls)
      _aliases=$(git config $_scope --get-regexp '^alias\.' 2>/dev/null || true)
      if [ -z "$_aliases" ]; then
        info "No aliases configured."
      else
        printf "%s\n" "$_aliases" | while IFS= read -r line; do
          _aname=$(printf '%s' "$line" | sed 's/^alias\.\([^ ]*\) .*/\1/')
          _acmd=$(printf '%s' "$line" | sed 's/^alias\.[^ ]* //')
          printf "  %s = %s\n" "$_aname" "$_acmd"
        done
      fi
      ;;
    add)
      [ $# -ge 2 ] || die "Usage: mygit aliases add <name> <command>"
      _aname="$1"; shift
      _acmd="$*"
      git config $_scope alias."$_aname" "$_acmd"
      success "Added alias: $_aname = $_acmd"
      ;;
    remove|rm)
      [ $# -ge 1 ] || die "Usage: mygit aliases remove <name>"
      _aname="$1"
      git config $_scope --unset alias."$_aname" 2>/dev/null || die "Alias '$_aname' not found."
      success "Removed alias: $_aname"
      ;;
    defaults)
      git config $_scope alias.co "checkout"
      git config $_scope alias.br "branch"
      git config $_scope alias.ci "commit"
      git config $_scope alias.st "status"
      git config $_scope alias.lg "log --oneline --graph --decorate"
      git config $_scope alias.unstage "reset HEAD --"
      git config $_scope alias.last "log -1 HEAD"
      git config $_scope alias.amend "commit --amend --no-edit"
      success "Installed default aliases: co, br, ci, st, lg, unstage, last, amend"
      ;;
    *)
      die "Unknown subcommand: '$_subcmd'. Use list, add, remove, or defaults."
      ;;
  esac
}

# ── defaults ──

cmd_defaults() {
  _scope="--global"
  _no_confirm=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --global)     _scope="--global"; shift ;;
      --local)      _scope="--local"; shift ;;
      --no-confirm) _no_confirm=true; shift ;;
      *) die "Unknown option: '$1'" ;;
    esac
  done

  if [ "$_no_confirm" = false ]; then
    printf "This will apply recommended defaults:\n"
    printf "  init.defaultBranch   = main\n"
    printf "  pull.rebase          = true\n"
    printf "  push.autoSetupRemote = true\n"
    printf "  core.autocrlf        = input\n"
    printf "  rerere.enabled       = true\n"
    printf "  diff.algorithm       = histogram\n"
    confirm "Apply these settings?" || { info "Aborted."; return; }
  fi

  _autocrlf="input"
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) _autocrlf="true" ;;
  esac

  git config $_scope init.defaultBranch main
  info "Set init.defaultBranch = main"
  git config $_scope pull.rebase true
  info "Set pull.rebase = true"
  git config $_scope push.autoSetupRemote true
  info "Set push.autoSetupRemote = true"
  git config $_scope core.autocrlf "$_autocrlf"
  info "Set core.autocrlf = $_autocrlf"
  git config $_scope rerere.enabled true
  info "Set rerere.enabled = true"
  git config $_scope diff.algorithm histogram
  info "Set diff.algorithm = histogram"

  success "Applied recommended defaults"
}

# ── setup ──

cmd_setup() {
  info "=== Git Configuration Setup ==="
  printf "\n"

  info "--- Step 1: User ---"
  cmd_user

  printf "\n"
  info "--- Step 2: Editor ---"
  cmd_editor

  printf "\n"
  info "--- Step 3: Credentials ---"
  cmd_credentials

  printf "\n"
  info "--- Step 4: Signing (optional) ---"
  if confirm "Configure commit signing?"; then
    printf "  1) GPG\n"
    printf "  2) SSH\n"
    printf "Choice [1-2]: "
    read -r _choice </dev/tty
    case "$_choice" in
      1)
        printf "GPG key ID: "
        read -r _keyid </dev/tty
        [ -n "$_keyid" ] && cmd_signing gpg "$_keyid"
        ;;
      2)
        printf "SSH key file: "
        read -r _keyfile </dev/tty
        [ -n "$_keyfile" ] && cmd_signing ssh "$_keyfile"
        ;;
      *) warn "Skipping signing configuration." ;;
    esac
  fi

  printf "\n"
  info "--- Step 5: Defaults ---"
  cmd_defaults

  printf "\n"
  info "=== Final Configuration ==="
  cmd_show
}

# ── Help ──

show_help() {
  cat <<'EOF'
Usage: mygit <command> [options]

Commands:
  show          Show git configuration summary (default)
  user          Configure user.name and user.email
  editor        Configure core.editor
  credentials   Configure credential.helper
  signing       Configure commit signing (GPG/SSH)
  aliases       Manage git aliases
  defaults      Apply recommended defaults
  setup         Interactive full setup wizard
  help          Show this help message

Options:
  --global      Use global scope (default)
  --local       Use local (repository) scope
  --system      Use system scope (show only)
  --version     Show version

Examples:
  mygit show
  mygit show --all
  mygit user "John Doe" john@example.com
  mygit user --name "John Doe" --email john@example.com
  mygit editor nvim
  mygit credentials store
  mygit credentials cache --timeout 7200
  mygit signing gpg ABC123
  mygit signing ssh ~/.ssh/id_ed25519.pub
  mygit signing off
  mygit aliases list
  mygit aliases add co checkout
  mygit aliases remove co
  mygit aliases defaults
  mygit defaults --no-confirm
  mygit setup
EOF
  exit 0
}

# ── Main dispatch ──

check_dep git

if [ $# -lt 1 ]; then
  show_help
fi

cmd="$1"
shift

case "$cmd" in
  show)        cmd_show "$@" ;;
  user)        cmd_user "$@" ;;
  editor)      cmd_editor "$@" ;;
  credentials) cmd_credentials "$@" ;;
  signing)     cmd_signing "$@" ;;
  aliases)     cmd_aliases "$@" ;;
  defaults)    cmd_defaults "$@" ;;
  setup)       cmd_setup "$@" ;;
  help|-h|--help) show_help ;;
  --version)   printf '%s\n' "$VERSION"; exit 0 ;;
  *)
    printf "Unknown command: %s\n" "$cmd" >&2
    exit 1
    ;;
esac
