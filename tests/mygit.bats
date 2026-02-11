#!/usr/bin/env bats

load test_helper

MYGIT="$SCRIPTS_DIR/mygit.sh"

setup() {
  setup_mygit_env
}

teardown() {
  teardown_mygit_env
}

# ── Help / dispatch ──

@test "no args shows help" {
  run "$MYGIT"
  assert_success
  assert_output --partial "Usage: mygit"
}

@test "help shows help" {
  run "$MYGIT" help
  assert_success
  assert_output --partial "Usage: mygit"
  assert_output --partial "Commands:"
}

@test "--help shows help" {
  run "$MYGIT" --help
  assert_success
  assert_output --partial "Usage: mygit"
}

@test "-h shows help" {
  run "$MYGIT" -h
  assert_success
  assert_output --partial "Usage: mygit"
}

@test "unknown command shows error" {
  run "$MYGIT" foobar
  assert_failure
  assert_output --partial "Unknown command: foobar"
}

# ── Version ──

@test "--version prints version" {
  run "$MYGIT" --version
  assert_success
  assert_output "1.0.1"
}

# ── User ──

@test "user sets name and email with positional args" {
  run "$MYGIT" user "John Doe" john@example.com
  assert_success
  assert_output --partial "Set user.name = John Doe"
  assert_output --partial "Set user.email = john@example.com"
  run git config --global user.name
  assert_output "John Doe"
  run git config --global user.email
  assert_output "john@example.com"
}

@test "user --name sets name only" {
  run "$MYGIT" user --name "Jane Doe"
  assert_success
  assert_output --partial "Set user.name = Jane Doe"
  refute_output --partial "Set user.email"
  run git config --global user.name
  assert_output "Jane Doe"
}

@test "user --email sets email only" {
  run "$MYGIT" user --email "jane@example.com"
  assert_success
  assert_output --partial "Set user.email = jane@example.com"
  refute_output --partial "Set user.name"
  run git config --global user.email
  assert_output "jane@example.com"
}

@test "user shows current config when values exist" {
  git config --global user.name "Existing User"
  git config --global user.email "existing@example.com"
  run git config --global user.name
  assert_output "Existing User"
}

# ── User --local ──

@test "user --local sets in local scope" {
  cd "$MYGIT_TEST_REPO"
  run "$MYGIT" user --local --name "Local User" --email "local@example.com"
  assert_success
  run git config --local user.name
  assert_output "Local User"
  run git config --local user.email
  assert_output "local@example.com"
}

# ── Editor ──

@test "editor sets editor directly" {
  run "$MYGIT" editor nvim
  assert_success
  assert_output --partial "Set core.editor = nvim"
  run git config --global core.editor
  assert_output "nvim"
}

@test "editor sets multi-word editor" {
  run "$MYGIT" editor code --wait
  assert_success
  assert_output --partial "Set core.editor = code --wait"
  run git config --global core.editor
  assert_output "code --wait"
}

# ── Credentials ──

@test "credentials store sets credential helper" {
  run "$MYGIT" credentials store
  assert_success
  assert_output --partial "Set credential.helper = store"
  run git config --global credential.helper
  assert_output "store"
}

@test "credentials cache sets credential helper with default timeout" {
  run "$MYGIT" credentials cache
  assert_success
  assert_output --partial "Set credential.helper = cache --timeout=3600"
  run git config --global credential.helper
  assert_output "cache --timeout=3600"
}

@test "credentials cache with custom timeout" {
  run "$MYGIT" credentials cache --timeout 7200
  assert_success
  assert_output --partial "Set credential.helper = cache --timeout=7200"
  run git config --global credential.helper
  assert_output "cache --timeout=7200"
}

# ── Signing ──

@test "signing gpg configures gpg signing" {
  run "$MYGIT" signing gpg ABC123DEF
  assert_success
  assert_output --partial "Configured GPG signing"
  run git config --global commit.gpgsign
  assert_output "true"
  run git config --global user.signingkey
  assert_output "ABC123DEF"
  run git config --global gpg.format
  assert_output "openpgp"
}

@test "signing ssh configures ssh signing" {
  run "$MYGIT" signing ssh /tmp/test_key.pub
  assert_success
  assert_output --partial "Configured SSH signing"
  run git config --global commit.gpgsign
  assert_output "true"
  run git config --global user.signingkey
  assert_output "/tmp/test_key.pub"
  run git config --global gpg.format
  assert_output "ssh"
}

@test "signing off disables signing" {
  git config --global commit.gpgsign true
  run "$MYGIT" signing off
  assert_success
  assert_output --partial "Disabled commit signing"
  run git config --global commit.gpgsign
  assert_output "false"
}

@test "signing with no args shows status" {
  run "$MYGIT" signing
  assert_success
  assert_output --partial "Signing: off"
}

@test "signing shows enabled status" {
  git config --global commit.gpgsign true
  git config --global user.signingkey "TESTKEY"
  git config --global gpg.format openpgp
  run "$MYGIT" signing
  assert_success
  assert_output --partial "Signing: OPENPGP (key: TESTKEY)"
}

# ── Aliases ──

@test "aliases list shows aliases" {
  git config --global alias.co "checkout"
  run "$MYGIT" aliases list
  assert_success
  assert_output --partial "co = checkout"
}

@test "aliases list with no aliases shows message" {
  run "$MYGIT" aliases list
  assert_success
  assert_output --partial "No aliases configured"
}

@test "aliases add and remove" {
  run "$MYGIT" aliases add myalias "log --oneline"
  assert_success
  assert_output --partial "Added alias: myalias = log --oneline"
  run git config --global alias.myalias
  assert_output "log --oneline"
  run "$MYGIT" aliases remove myalias
  assert_success
  assert_output --partial "Removed alias: myalias"
}

@test "aliases defaults installs default aliases" {
  run "$MYGIT" aliases defaults
  assert_success
  assert_output --partial "Installed default aliases"
  run git config --global alias.co
  assert_output "checkout"
  run git config --global alias.br
  assert_output "branch"
  run git config --global alias.ci
  assert_output "commit"
  run git config --global alias.st
  assert_output "status"
  run git config --global alias.lg
  assert_output "log --oneline --graph --decorate"
  run git config --global alias.unstage
  assert_output "reset HEAD --"
  run git config --global alias.last
  assert_output "log -1 HEAD"
  run git config --global alias.amend
  assert_output "commit --amend --no-edit"
}

# ── Defaults ──

@test "defaults applies all defaults with --no-confirm" {
  run "$MYGIT" defaults --no-confirm
  assert_success
  assert_output --partial "Applied recommended defaults"
  run git config --global init.defaultBranch
  assert_output "main"
  run git config --global pull.rebase
  assert_output "true"
  run git config --global push.autoSetupRemote
  assert_output "true"
  run git config --global core.autocrlf
  assert_output "input"
  run git config --global rerere.enabled
  assert_output "true"
  run git config --global diff.algorithm
  assert_output "histogram"
}

# ── Show ──

@test "show displays config summary" {
  git config --global user.name "Test User"
  git config --global user.email "test@example.com"
  git config --global core.editor "vim"
  run "$MYGIT" show
  assert_success
  assert_output --partial "Git configuration (global)"
  assert_output --partial "Test User"
  assert_output --partial "test@example.com"
  assert_output --partial "vim"
}

@test "show --all lists all config" {
  git config --global user.name "Test User"
  run "$MYGIT" show --all
  assert_success
  assert_output --partial "user.name=Test User"
}

@test "show --local shows local scope" {
  cd "$MYGIT_TEST_REPO"
  git config --local user.name "Local User"
  run "$MYGIT" show --local
  assert_success
  assert_output --partial "Git configuration (local)"
  assert_output --partial "Local User"
}
