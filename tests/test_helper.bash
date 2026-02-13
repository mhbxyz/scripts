#!/usr/bin/env bash

# Shared test helper for BATS test suites
# Load BATS libraries and define isolation helpers

# ── Load BATS libraries (Arch: /usr/lib/bats/bats-*) ──

load '/usr/lib/bats/bats-support/load'
load '/usr/lib/bats/bats-assert/load'
load '/usr/lib/bats/bats-file/load'

# ── Constants ──

SCRIPTS_DIR="$(cd "$BATS_TEST_DIRNAME/../shell" && pwd)"

# ── GPG isolation ──

setup_gpg_home() {
  export GNUPGHOME="$(mktemp -d)"
  chmod 700 "$GNUPGHOME"
  # Loopback pinentry avoids hangs (no tty in BATS)
  printf "pinentry-mode loopback\n" > "$GNUPGHOME/gpg.conf"
  printf "allow-loopback-pinentry\n" > "$GNUPGHOME/gpg-agent.conf"
  gpgconf --kill gpg-agent 2>/dev/null || true
}

teardown_gpg_home() {
  gpgconf --kill gpg-agent 2>/dev/null || true
  rm -rf "$GNUPGHOME"
  unset GNUPGHOME
}

# Generates a test ed25519 key; sets GPG_TEST_EMAIL and GPG_TEST_FINGERPRINT
generate_test_key() {
  GPG_TEST_EMAIL="testkey-$$@test.com"
  local param_file="$GNUPGHOME/batch.txt"
  cat > "$param_file" <<EOF
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Key-Usage: sign
Subkey-Type: ecdh
Subkey-Curve: cv25519
Subkey-Usage: encrypt
Name-Real: Test User
Name-Email: $GPG_TEST_EMAIL
Expire-Date: 1y
EOF
  gpg --batch --generate-key "$param_file" 2>/dev/null
  GPG_TEST_FINGERPRINT=$(gpg --list-secret-keys --with-colons "$GPG_TEST_EMAIL" 2>/dev/null \
    | awk -F: '/^fpr:/ { print $10; exit }')
}

# ── SSH isolation (override HOME) ──

setup_ssh_home() {
  export HOME_ORIG="$HOME"
  export HOME="$(mktemp -d)"
  mkdir -p "$HOME/.ssh"
}

teardown_ssh_home() {
  rm -rf "$HOME"
  export HOME="$HOME_ORIG"
  unset HOME_ORIG
}

# ── Git config isolation ──

setup_git_config() {
  export GIT_CONFIG_GLOBAL="$(mktemp)"
}

teardown_git_config() {
  rm -f "$GIT_CONFIG_GLOBAL"
  unset GIT_CONFIG_GLOBAL
}

# ── Backup environment isolation ──

setup_backup_env() {
  export HOME_ORIG="$HOME"
  export HOME="$(mktemp -d)"

  # Create a realistic home structure
  mkdir -p "$HOME/Documents" "$HOME/Pictures" "$HOME/.config"
  printf "doc1\n" > "$HOME/Documents/file1.txt"
  printf "doc2\n" > "$HOME/Documents/file2.txt"
  printf "pic\n"  > "$HOME/Pictures/photo.jpg"
  printf "cfg\n"  > "$HOME/.config/settings.conf"

  # Directories that should be excluded by default
  mkdir -p "$HOME/.cache" "$HOME/.local" "$HOME/node_modules"
  printf "cache\n" > "$HOME/.cache/cached.tmp"
  printf "local\n" > "$HOME/.local/state.db"
  printf "nm\n"    > "$HOME/node_modules/pkg.js"

  # Create a fake mount point
  FAKE_MOUNT="$(mktemp -d)"
  FAKE_DRIVE="$FAKE_MOUNT/TestDrive"
  mkdir -p "$FAKE_DRIVE"

  export HOMEBACKUP_MOUNT_BASES="$FAKE_MOUNT"
  export FAKE_MOUNT FAKE_DRIVE
}

teardown_backup_env() {
  rm -rf "$HOME"
  rm -rf "$FAKE_MOUNT"
  export HOME="$HOME_ORIG"
  unset HOME_ORIG HOMEBACKUP_MOUNT_BASES FAKE_MOUNT FAKE_DRIVE
}

# ── Install environment isolation ──

setup_install_env() {
  FAKE_REPO="$(mktemp -d)"
  mkdir -p "$FAKE_REPO/shell"
  # Create dummy shell scripts in the fake repo (with VERSION)
  for script in gpgkeys.sh sshkeys.sh homebackup.sh sortdownloads.sh mygit.sh dotfiles.sh mkproject.sh cleanup.sh; do
    printf '#!/bin/sh\nVERSION="1.0.0"\necho "%s"\n' "$script" > "$FAKE_REPO/shell/$script"
  done
  # Create dummy binaries in the fake repo (release structure) with .sha256 sidecars
  for tag in imgstotxt-latest pdftoimgs-latest keepalive-latest; do
    name="${tag%-latest}"
    mkdir -p "$FAKE_REPO/$tag"
    for platform in linux-x86_64 darwin-x86_64 darwin-arm64; do
      _binpath="$FAKE_REPO/$tag/$name-$platform"
      printf '#!/bin/sh\necho "%s 1.0.0"\n' "$name" > "$_binpath"
      sha256sum "$_binpath" | cut -d' ' -f1 > "$_binpath.sha256"
    done
  done
  export SCRIPTS_REPO_URL="file://$FAKE_REPO"
  export RELEASES_BASE_URL="file://$FAKE_REPO"
  export INSTALL_DIR="$(mktemp -d)"
  export FAKE_REPO
}

teardown_install_env() {
  rm -rf "$FAKE_REPO" "$INSTALL_DIR"
  unset SCRIPTS_REPO_URL RELEASES_BASE_URL INSTALL_DIR FAKE_REPO
}

# ── Sortdownloads environment isolation ──

setup_sortdownloads_env() {
  export HOME_ORIG="$HOME"
  export HOME="$(mktemp -d)"

  # Force English locale for deterministic category names
  export LC_ALL_ORIG="${LC_ALL:-}"
  export LANG_ORIG="${LANG:-}"
  export LC_ALL="en_US.UTF-8"
  export LANG="en_US.UTF-8"

  DOWNLOADS="$HOME/Downloads"
  mkdir -p "$DOWNLOADS"

  # Test files for each category
  printf "pdf" > "$DOWNLOADS/report.pdf"
  printf "jpg" > "$DOWNLOADS/photo.jpg"
  printf "mp4" > "$DOWNLOADS/video.mp4"
  printf "mp3" > "$DOWNLOADS/song.mp3"
  printf "zip" > "$DOWNLOADS/archive.zip"
  printf "deb" > "$DOWNLOADS/installer.deb"
  printf "sh"  > "$DOWNLOADS/script.sh"
  printf "ttf" > "$DOWNLOADS/font.ttf"
  printf "iso" > "$DOWNLOADS/image.iso"
  printf "json" > "$DOWNLOADS/data.json"
  printf "noext" > "$DOWNLOADS/noextension"

  # Edge cases
  printf "hidden" > "$DOWNLOADS/.hidden_file"
  printf "part"   > "$DOWNLOADS/downloading.part"
  printf "crdl"   > "$DOWNLOADS/inprogress.crdownload"
  ln -s "$DOWNLOADS/report.pdf" "$DOWNLOADS/symlink.pdf"
  mkdir -p "$DOWNLOADS/subdirectory"

  # Mock systemd dir
  SORTDOWNLOADS_MOCK_DIR="$(mktemp -d)"
  export SORTDOWNLOADS_MOCK_DIR DOWNLOADS
}

teardown_sortdownloads_env() {
  rm -rf "$HOME"
  rm -rf "$SORTDOWNLOADS_MOCK_DIR"
  export HOME="$HOME_ORIG"
  export LC_ALL="$LC_ALL_ORIG"
  export LANG="$LANG_ORIG"
  unset HOME_ORIG DOWNLOADS SORTDOWNLOADS_MOCK_DIR LC_ALL_ORIG LANG_ORIG
}

# ── Mygit environment isolation ──

setup_mygit_env() {
  export GIT_CONFIG_GLOBAL="$(mktemp)"
  export HOME_ORIG="$HOME"
  export HOME="$(mktemp -d)"
  # Init a git repo so --local scope works
  git init "$HOME/repo" >/dev/null 2>&1
  export MYGIT_TEST_REPO="$HOME/repo"
}

teardown_mygit_env() {
  rm -f "$GIT_CONFIG_GLOBAL"
  rm -rf "$HOME"
  export HOME="$HOME_ORIG"
  unset GIT_CONFIG_GLOBAL HOME_ORIG MYGIT_TEST_REPO
}

# ── Dotfiles environment isolation ──

setup_dotfiles_env() {
  export HOME_ORIG="$HOME"
  export HOME="$(mktemp -d)"

  # Create realistic config files
  mkdir -p "$HOME/.config/nvim" "$HOME/.ssh"
  printf 'alias ll="ls -la"\n' > "$HOME/.bashrc"
  printf 'set number\n' > "$HOME/.config/nvim/init.lua"
  printf '[user]\n  name = Test\n' > "$HOME/.gitconfig"

  # Use a non-existing path so init can create it
  DOTFILES_DIR="$(mktemp -d)/dotfiles"
  export DOTFILES_DIR
}

teardown_dotfiles_env() {
  rm -rf "$HOME"
  rm -rf "$(dirname "$DOTFILES_DIR")"
  export HOME="$HOME_ORIG"
  unset HOME_ORIG DOTFILES_DIR
}

# ── Mkproject environment isolation ──

setup_mkproject_env() {
  export HOME_ORIG="$HOME"
  export HOME="$(mktemp -d)"
  export GIT_CONFIG_GLOBAL="$(mktemp)"
  git config --global user.name "Test User" 2>/dev/null || true
  git config --global user.email "test@test.com" 2>/dev/null || true

  PROJECTS_DIR="$(mktemp -d)"
  export PROJECTS_DIR
}

teardown_mkproject_env() {
  rm -f "$GIT_CONFIG_GLOBAL"
  rm -rf "$HOME"
  rm -rf "$PROJECTS_DIR"
  export HOME="$HOME_ORIG"
  unset HOME_ORIG GIT_CONFIG_GLOBAL PROJECTS_DIR
}

# ── Cleanup environment isolation ──

setup_cleanup_env() {
  export HOME_ORIG="$HOME"
  export HOME="$(mktemp -d)"

  # Create structure for cleanup targets
  mkdir -p "$HOME/.cache" "$HOME/.local/share/Trash" "$HOME/Downloads"
}

teardown_cleanup_env() {
  rm -rf "$HOME"
  export HOME="$HOME_ORIG"
  unset HOME_ORIG
}

# ── Mock PATH ──

setup_mocks() {
  export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"
}
