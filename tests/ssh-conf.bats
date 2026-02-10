#!/usr/bin/env bats

load test_helper

SSHCONF="$SCRIPTS_DIR/ssh-conf.sh"

setup() {
  setup_ssh_home
}

teardown() {
  teardown_ssh_home
}

# ── Help ──

@test "no arguments shows help" {
  run "$SSHCONF"
  assert_success
  assert_output --partial "Usage:"
}

@test "help command shows help" {
  run "$SSHCONF" help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "add"
  assert_output --partial "remove"
}

@test "--help shows help" {
  run "$SSHCONF" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "unknown command shows error" {
  run "$SSHCONF" foobar
  assert_output --partial "Unknown command: foobar"
}

# ── Add + list ──

@test "add host and list it" {
  run "$SSHCONF" add myserver example.com user1
  assert_success
  assert_output --partial "Added host 'myserver'"

  run "$SSHCONF" list
  assert_success
  assert_output --partial "myserver"
}

@test "add host with identity file" {
  run "$SSHCONF" add myserver example.com user1 ~/.ssh/id_rsa
  assert_success

  run "$SSHCONF" show myserver
  assert_success
  assert_output --partial "IdentityFile"
  assert_output --partial "id_rsa"
}

@test "add multiple hosts" {
  run "$SSHCONF" add server1 host1.com user1
  assert_success

  run "$SSHCONF" add server2 host2.com user2
  assert_success

  run "$SSHCONF" list
  assert_success
  assert_output --partial "server1"
  assert_output --partial "server2"
}

# ── Duplicate detection ──

@test "add duplicate host fails" {
  run "$SSHCONF" add myserver example.com user1
  assert_success

  run "$SSHCONF" add myserver other.com user2
  assert_failure
  assert_output --partial "already exists"
}

# ── Show ──

@test "show displays host block" {
  run "$SSHCONF" add myserver example.com user1
  assert_success

  run "$SSHCONF" show myserver
  assert_success
  assert_output --partial "Host myserver"
  assert_output --partial "HostName example.com"
  assert_output --partial "User user1"
}

@test "show nonexistent host outputs nothing" {
  run "$SSHCONF" show nonexistent
  assert_success
  assert_output ""
}

# ── Remove ──

@test "remove existing host" {
  run "$SSHCONF" add myserver example.com user1
  assert_success

  run "$SSHCONF" remove myserver
  assert_success
  assert_output --partial "Removed host 'myserver'"

  # Verify it's gone
  run "$SSHCONF" list
  refute_output --partial "myserver"
}

@test "remove nonexistent host fails" {
  run "$SSHCONF" remove nonexistent
  assert_failure
  assert_output --partial "not found"
}

@test "remove creates backup" {
  run "$SSHCONF" add myserver example.com user1
  assert_success

  run "$SSHCONF" remove myserver
  assert_success
  assert_file_exists "$HOME/.ssh/config.bak"
}

# ── Backup ──

@test "backup creates .bak file" {
  run "$SSHCONF" add myserver example.com user1
  assert_success

  run "$SSHCONF" backup
  assert_success
  assert_output --partial "Backup saved"
  assert_file_exists "$HOME/.ssh/config.bak"
}

# ── Edge cases ──

@test "add with missing arguments shows help" {
  run "$SSHCONF" add myserver
  assert_success
  assert_output --partial "Usage:"
}

@test "remove with missing arguments shows help" {
  run "$SSHCONF" remove
  assert_success
  assert_output --partial "Usage:"
}

@test "list on empty config outputs nothing" {
  run "$SSHCONF" list
  assert_success
  assert_output ""
}
