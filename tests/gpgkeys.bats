#!/usr/bin/env bats

load test_helper

GPGKEYS="$SCRIPTS_DIR/gpgkeys.sh"

# ── Shared GPG home for tests that only read keys ──

setup_file() {
  setup_gpg_home
  setup_git_config
  # Export for child processes (BATS runs tests in subshells)
  export GNUPGHOME GIT_CONFIG_GLOBAL
  # Generate one shared key for read-only tests
  generate_test_key
  export GPG_TEST_EMAIL GPG_TEST_FINGERPRINT
}

teardown_file() {
  teardown_git_config
  teardown_gpg_home
}

# ── Help / dispatch (no GPG needed) ──

@test "no arguments shows help" {
  run "$GPGKEYS"
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "Commands:"
}

@test "help command shows help" {
  run "$GPGKEYS" help
  assert_success
  assert_output --partial "Usage:"
}

@test "--help shows help" {
  run "$GPGKEYS" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "-h shows help" {
  run "$GPGKEYS" -h
  assert_success
  assert_output --partial "Usage:"
}

@test "unknown command shows error and help" {
  run "$GPGKEYS" foobar
  assert_success
  assert_output --partial "Unknown command: foobar"
  assert_output --partial "Usage:"
}

# ── Argument errors ──

@test "generate with unknown flag fails" {
  run "$GPGKEYS" generate --bogus
  assert_failure
  assert_output --partial "Unknown option: --bogus"
}

@test "generate with invalid algo fails" {
  run "$GPGKEYS" generate --name "Test" --email "t@t.com" --algo dsa1024 --no-sign --no-github
  assert_failure
  assert_output --partial "Unsupported algorithm"
}

@test "import without arguments fails" {
  run "$GPGKEYS" import
  assert_failure
  assert_output --partial "Provide a file path or --dir"
}

@test "import with nonexistent directory fails" {
  run "$GPGKEYS" import --dir /nonexistent/path
  assert_failure
  assert_output --partial "Directory not found"
}

@test "import with nonexistent file fails" {
  run "$GPGKEYS" import /nonexistent/file.asc
  assert_failure
  assert_output --partial "File not found"
}

@test "list with unknown flag fails" {
  run "$GPGKEYS" list --bogus
  assert_failure
  assert_output --partial "Unknown option: --bogus"
}

@test "backup with unknown flag fails" {
  run "$GPGKEYS" backup --bogus
  assert_failure
  assert_output --partial "Unknown option: --bogus"
}

# ── check_dep ──

@test "missing gpg dependency shows error" {
  run env PATH=/usr/bin/nonexistent "$GPGKEYS" help
  assert_failure
  assert_output --partial "gpg"
  assert_output --partial "required"
}

# ── Tests using the shared key ──

@test "list shows shared key" {
  run "$GPGKEYS" list
  assert_success
  assert_output --partial "$GPG_TEST_EMAIL"
}

@test "list --secret shows shared key" {
  run "$GPGKEYS" list --secret
  assert_success
  assert_output --partial "$GPG_TEST_EMAIL"
}

@test "export to stdout produces ASCII armor" {
  run "$GPGKEYS" export "$GPG_TEST_EMAIL"
  assert_success
  assert_output --partial "BEGIN PGP PUBLIC KEY BLOCK"
}

@test "export to file creates ASCII armored file" {
  outfile="$(mktemp)"
  run "$GPGKEYS" export "$GPG_TEST_EMAIL" -o "$outfile"
  assert_success
  assert_output --partial "Public key written to"

  run cat "$outfile"
  assert_output --partial "BEGIN PGP PUBLIC KEY BLOCK"
  rm -f "$outfile"
}

@test "delete without --force aborts on empty stdin" {
  run "$GPGKEYS" delete "$GPG_TEST_EMAIL"
  assert_success
  assert_output --partial "Aborted"

  # Key should still exist
  run "$GPGKEYS" list
  assert_output --partial "$GPG_TEST_EMAIL"
}

@test "backup creates files" {
  backup_dir="$(mktemp -d)"
  run "$GPGKEYS" backup --dir "$backup_dir"
  assert_success
  assert_output --partial "Backup complete"
  assert [ "$(ls "$backup_dir"/gpg-public-keys-*.asc 2>/dev/null | wc -l)" -ge 1 ]
  assert [ "$(ls "$backup_dir"/gpg-secret-keys-*.asc 2>/dev/null | wc -l)" -ge 1 ]
  assert [ "$(ls "$backup_dir"/gpg-ownertrust-*.txt 2>/dev/null | wc -l)" -ge 1 ]
  rm -rf "$backup_dir"
}

# ── Generate + delete lifecycle (needs own key) ──

@test "generate ed25519 then delete with --force" {
  run "$GPGKEYS" generate --name "Lifecycle" --email "lifecycle@test.com" --algo ed25519 --no-sign --no-github
  assert_success
  assert_output --partial "Key generated"

  # Get fingerprint for deletion
  fp=$(gpg --list-secret-keys --with-colons "lifecycle@test.com" 2>/dev/null \
    | awk -F: '/^fpr:/ { print $10; exit }')

  run "$GPGKEYS" delete "$fp" --force
  assert_success
  assert_output --partial "deleted"

  run "$GPGKEYS" list
  refute_output --partial "lifecycle@test.com"
}

# ── Backup + import roundtrip ──

@test "backup then import restores keys" {
  # Generate a temporary key
  run "$GPGKEYS" generate --name "Backup User" --email "backup@test.com" --algo ed25519 --no-sign --no-github
  assert_success

  backup_dir="$(mktemp -d)"
  run "$GPGKEYS" backup --dir "$backup_dir"
  assert_success

  # Delete the key
  fp=$(gpg --list-secret-keys --with-colons "backup@test.com" 2>/dev/null \
    | awk -F: '/^fpr:/ { print $10; exit }')
  run "$GPGKEYS" delete "$fp" --force
  assert_success

  # Import from backup
  run "$GPGKEYS" import --dir "$backup_dir"
  assert_success
  assert_output --partial "Import complete"

  # Key should be back
  run "$GPGKEYS" list
  assert_output --partial "backup@test.com"

  # Cleanup: delete imported key
  fp=$(gpg --list-secret-keys --with-colons "backup@test.com" 2>/dev/null \
    | awk -F: '/^fpr:/ { print $10; exit }')
  gpg --batch --yes --delete-secret-and-public-key "$fp" 2>/dev/null || true

  rm -rf "$backup_dir"
}

# ── RSA variant (slow — skipped by default, run with BATS_TEST_RSA=1) ──

@test "generate rsa4096 key" {
  if [ "${BATS_TEST_RSA:-}" != "1" ]; then
    skip "RSA test is slow; set BATS_TEST_RSA=1 to run"
  fi

  run "$GPGKEYS" generate --name "RSA User" --email "rsa@test.com" --algo rsa4096 --no-sign --no-github
  assert_success
  assert_output --partial "Key generated"

  run gpg --list-keys --keyid-format long "rsa@test.com"
  assert_success
  assert_output --partial "rsa4096"

  fp=$(gpg --list-secret-keys --with-colons "rsa@test.com" 2>/dev/null \
    | awk -F: '/^fpr:/ { print $10; exit }')
  gpg --batch --yes --delete-secret-and-public-key "$fp" 2>/dev/null || true
}

# ── GitHub integration (mocked) ──

@test "github list with mock gh" {
  setup_mocks
  run "$GPGKEYS" github list
  assert_success
  assert_output --partial "DEADBEEF1234"
}

@test "github add with mock gh" {
  setup_mocks
  run "$GPGKEYS" github add "$GPG_TEST_EMAIL"
  assert_success
  assert_output --partial "GPG key added"
}

@test "github config configures git signing" {
  run "$GPGKEYS" github config "$GPG_TEST_EMAIL"
  assert_success
  assert_output --partial "Git configured for GPG signing"

  run git config --file "$GIT_CONFIG_GLOBAL" user.signingkey
  assert_success

  run git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign
  assert_success
  assert_output "true"
}

@test "github without subcommand shows usage" {
  setup_mocks
  run "$GPGKEYS" github
  assert_failure
  assert_output --partial "Usage:"
}

@test "github with invalid action fails" {
  setup_mocks
  run "$GPGKEYS" github bogus
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

  run "$GPGKEYS" github add "$GPG_TEST_EMAIL"
  assert_failure
  assert_output --partial "Not authenticated"

  rm -rf "$mock_dir"
}
