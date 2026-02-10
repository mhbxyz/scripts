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

# ── Mock PATH ──

setup_mocks() {
  export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"
}
