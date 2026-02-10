#!/usr/bin/env bats

load test_helper

SSHKEYS="$SCRIPTS_DIR/sshkeys.sh"

setup() {
  setup_ssh_home
}

teardown() {
  teardown_ssh_home
}

# ── Help / dispatch ──

@test "no arguments shows help" {
  run "$SSHKEYS"
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "Commands:"
}

@test "help command shows help" {
  run "$SSHKEYS" help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "generate"
  assert_output --partial "config"
}

@test "--help shows help" {
  run "$SSHKEYS" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "-h shows help" {
  run "$SSHKEYS" -h
  assert_success
  assert_output --partial "Usage:"
}

@test "unknown command shows error" {
  run "$SSHKEYS" foobar
  assert_success
  assert_output --partial "Unknown command: foobar"
  assert_output --partial "Usage:"
}

# ── Generate ──

@test "generate ed25519 with --no-passphrase" {
  run "$SSHKEYS" generate --email "test@example.com" --no-passphrase --no-clipboard --no-github
  assert_success
  assert_output --partial "Key generated"
  assert_file_exists "$HOME/.ssh/id_ed25519"
  assert_file_exists "$HOME/.ssh/id_ed25519.pub"
}

@test "generate with --name custom" {
  run "$SSHKEYS" generate --email "test@example.com" --name id_custom --no-passphrase --no-clipboard --no-github
  assert_success
  assert_output --partial "Key generated"
  assert_file_exists "$HOME/.ssh/id_custom"
  assert_file_exists "$HOME/.ssh/id_custom.pub"
}

@test "generate with --comment" {
  run "$SSHKEYS" generate --email "test@example.com" --comment "work laptop" --no-passphrase --no-clipboard --no-github
  assert_success
  assert_output --partial "test@example.com (work laptop)"
}

@test "generate with unknown flag fails" {
  run "$SSHKEYS" generate --bogus
  assert_failure
  assert_output --partial "Unknown option: --bogus"
}

@test "generate with invalid type fails" {
  run "$SSHKEYS" generate --email "test@example.com" --type dsa --no-passphrase --no-clipboard --no-github
  assert_failure
  assert_output --partial "Unsupported key type"
}

@test "generate with --host creates config block" {
  run "$SSHKEYS" generate --email "test@example.com" --name id_hosttest --host github.com --alias github --no-passphrase --no-clipboard --no-github
  assert_success
  assert_output --partial "SSH config updated with alias 'github'"
  assert_file_exists "$HOME/.ssh/config"

  run cat "$HOME/.ssh/config"
  assert_output --partial "Host github"
  assert_output --partial "HostName github.com"
  assert_output --partial "IdentityFile"
}

@test "generate with --no-config skips config block" {
  run "$SSHKEYS" generate --email "test@example.com" --name id_noconf --host github.com --no-config --no-passphrase --no-clipboard --no-github
  assert_success
  refute_output --partial "SSH config updated"
}

# ── List ──

@test "list shows generated keys" {
  ssh-keygen -t ed25519 -C "list@test.com" -f "$HOME/.ssh/id_listtest" -N "" >/dev/null 2>&1

  run "$SSHKEYS" list
  assert_success
  assert_output --partial "list@test.com"
}

@test "list with no keys shows message" {
  run "$SSHKEYS" list
  assert_success
  assert_output --partial "No SSH keys found"
}

# ── Delete ──

@test "delete with --force removes key" {
  ssh-keygen -t ed25519 -C "del@test.com" -f "$HOME/.ssh/id_deltest" -N "" >/dev/null 2>&1

  run "$SSHKEYS" delete id_deltest --force
  assert_success
  assert_output --partial "deleted"
  assert_file_not_exists "$HOME/.ssh/id_deltest"
  assert_file_not_exists "$HOME/.ssh/id_deltest.pub"
}

@test "delete without --force aborts on empty stdin" {
  ssh-keygen -t ed25519 -C "del@test.com" -f "$HOME/.ssh/id_deltest" -N "" >/dev/null 2>&1

  run "$SSHKEYS" delete id_deltest
  assert_success
  assert_output --partial "Aborted"
  assert_file_exists "$HOME/.ssh/id_deltest"
}

@test "delete nonexistent key fails" {
  run "$SSHKEYS" delete nonexistent --force
  assert_failure
  assert_output --partial "not found"
}

# ── Config add ──

@test "config add and list" {
  run "$SSHKEYS" config add myserver example.com user1
  assert_success
  assert_output --partial "Added host 'myserver'"

  run "$SSHKEYS" config list
  assert_success
  assert_output --partial "myserver"
}

@test "config add with identity" {
  run "$SSHKEYS" config add myserver example.com user1 --identity ~/.ssh/id_rsa
  assert_success

  run "$SSHKEYS" config show myserver
  assert_success
  assert_output --partial "IdentityFile"
  assert_output --partial "id_rsa"
}

@test "config add duplicate fails" {
  run "$SSHKEYS" config add myserver example.com user1
  assert_success

  run "$SSHKEYS" config add myserver other.com user2
  assert_failure
  assert_output --partial "already exists"
}

# ── Config show ──

@test "config show displays block" {
  run "$SSHKEYS" config add myserver example.com user1
  assert_success

  run "$SSHKEYS" config show myserver
  assert_success
  assert_output --partial "Host myserver"
  assert_output --partial "HostName example.com"
  assert_output --partial "User user1"
}

@test "config show nonexistent host outputs nothing" {
  run "$SSHKEYS" config show nonexistent
  assert_success
  assert_output ""
}

# ── Config remove ──

@test "config remove with --force removes host" {
  run "$SSHKEYS" config add myserver example.com user1
  assert_success

  run "$SSHKEYS" config remove myserver --force
  assert_success
  assert_output --partial "Removed host 'myserver'"

  run "$SSHKEYS" config list
  refute_output --partial "myserver"
}

@test "config remove nonexistent host fails" {
  run "$SSHKEYS" config remove nonexistent --force
  assert_failure
  assert_output --partial "not found"
}

@test "config remove creates backup" {
  run "$SSHKEYS" config add myserver example.com user1
  assert_success

  run "$SSHKEYS" config remove myserver --force
  assert_success
  assert_file_exists "$HOME/.ssh/config.bak"
}

# ── Config backup ──

@test "config backup creates .bak file" {
  run "$SSHKEYS" config add myserver example.com user1
  assert_success

  run "$SSHKEYS" config backup
  assert_success
  assert_output --partial "Backup saved"
  assert_file_exists "$HOME/.ssh/config.bak"
}

# ── Config dispatch ──

@test "config without subcommand shows usage" {
  run "$SSHKEYS" config
  assert_failure
  assert_output --partial "Usage:"
}

@test "config with invalid action fails" {
  run "$SSHKEYS" config bogus
  assert_failure
  assert_output --partial "Unknown config action"
}

# ── Config list empty ──

@test "config list on empty config outputs nothing" {
  run "$SSHKEYS" config list
  assert_success
  assert_output ""
}

# ── GitHub (mocked) ──

@test "github list with mock gh" {
  setup_mocks
  run "$SSHKEYS" github list
  assert_success
  assert_output --partial "12345"
}

@test "github add with mock gh" {
  setup_mocks
  ssh-keygen -t ed25519 -C "gh@test.com" -f "$HOME/.ssh/id_ghtest" -N "" >/dev/null 2>&1

  run "$SSHKEYS" github add "$HOME/.ssh/id_ghtest.pub"
  assert_success
  assert_output --partial "SSH key added"
}

@test "github without subcommand shows usage" {
  setup_mocks
  run "$SSHKEYS" github
  assert_failure
  assert_output --partial "Usage:"
}

@test "github with invalid action fails" {
  setup_mocks
  run "$SSHKEYS" github bogus
  assert_failure
  assert_output --partial "Unknown github action"
}

@test "github add without gh auth fails" {
  mock_dir="$(mktemp -d)"
  cat > "$mock_dir/gh" <<'MOCK'
#!/bin/sh
case "$1" in
  auth) exit 1 ;;
esac
exit 1
MOCK
  chmod +x "$mock_dir/gh"
  export PATH="$mock_dir:$PATH"

  ssh-keygen -t ed25519 -C "noauth@test.com" -f "$HOME/.ssh/id_noauth" -N "" >/dev/null 2>&1

  run "$SSHKEYS" github add "$HOME/.ssh/id_noauth.pub"
  assert_failure
  assert_output --partial "Not authenticated"

  rm -rf "$mock_dir"
}
