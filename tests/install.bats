#!/usr/bin/env bats

load test_helper

INSTALL_SH="$BATS_TEST_DIRNAME/../install.sh"

setup() {
  setup_install_env
}

teardown() {
  teardown_install_env
}

# ── Help / dispatch ──

@test "help shows usage" {
  run "$INSTALL_SH" help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "install"
  assert_output --partial "uninstall"
  assert_output --partial "update"
}

@test "--help shows usage" {
  run "$INSTALL_SH" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "-h shows usage" {
  run "$INSTALL_SH" -h
  assert_success
  assert_output --partial "Usage:"
}

@test "unknown command fails" {
  run "$INSTALL_SH" foobar
  assert_failure
  assert_output --partial "Unknown command"
}

# ── Argument validation ──

@test "--only with unknown script name fails" {
  run "$INSTALL_SH" install --only "nonexistent"
  assert_failure
  assert_output --partial "Unknown script"
}

@test "--only with empty string fails" {
  run "$INSTALL_SH" install --only ""
  assert_failure
  assert_output --partial "--only requires at least one script name"
}

@test "--only without argument fails" {
  run "$INSTALL_SH" install --only
  assert_failure
  assert_output --partial "--only requires an argument"
}

@test "--dir without argument fails" {
  run "$INSTALL_SH" install --dir
  assert_failure
  assert_output --partial "--dir requires an argument"
}

# ── Install e2e ──

@test "install --all installs all 6 scripts" {
  run "$INSTALL_SH" install --all
  assert_success
  assert_output --partial "Installed 6 script(s)"
  for name in gpgkeys sshkeys homebackup sortdownloads imgstotxt pdftoimgs; do
    assert [ -f "$INSTALL_DIR/$name" ]
  done
}

@test "install --only installs specific scripts" {
  run "$INSTALL_SH" install --only "gpgkeys sshkeys"
  assert_success
  assert_output --partial "Installed: gpgkeys (1.0.0)"
  assert_output --partial "Installed: sshkeys (1.0.0)"
  assert [ -f "$INSTALL_DIR/gpgkeys" ]
  assert [ -f "$INSTALL_DIR/sshkeys" ]
  assert [ ! -f "$INSTALL_DIR/homebackup" ]
}

@test "install --only single script" {
  run "$INSTALL_SH" install --only "homebackup"
  assert_success
  assert_output --partial "Installed: homebackup (1.0.0)"
  assert_output --partial "Installed 1 script(s)"
  assert [ -f "$INSTALL_DIR/homebackup" ]
}

@test "installed scripts are executable" {
  run "$INSTALL_SH" install --all
  assert_success
  for name in gpgkeys sshkeys homebackup; do
    assert [ -x "$INSTALL_DIR/$name" ]
  done
}

@test "installed scripts have no .sh extension" {
  run "$INSTALL_SH" install --all
  assert_success
  run ls "$INSTALL_DIR"
  refute_output --partial ".sh"
}

@test "install --dir uses custom directory" {
  custom_dir="$(mktemp -d)"
  run "$INSTALL_SH" install --all --dir "$custom_dir"
  assert_success
  assert [ -f "$custom_dir/gpgkeys" ]
  assert [ -f "$custom_dir/sshkeys" ]
  rm -rf "$custom_dir"
}

@test "install creates INSTALL_DIR if missing" {
  rm -rf "$INSTALL_DIR"
  run "$INSTALL_SH" install --only "gpgkeys"
  assert_success
  assert [ -d "$INSTALL_DIR" ]
  assert [ -f "$INSTALL_DIR/gpgkeys" ]
}

# ── PATH warning ──

@test "install warns when INSTALL_DIR is not in PATH" {
  # Use a directory that is definitely not in PATH
  custom_dir="$(mktemp -d)/not-in-path"
  run "$INSTALL_SH" install --only "gpgkeys" --dir "$custom_dir"
  assert_success
  assert_output --partial "is not in your PATH"
  rm -rf "$(dirname "$custom_dir")"
}

@test "install does not warn when INSTALL_DIR is in PATH" {
  export PATH="$INSTALL_DIR:$PATH"
  run "$INSTALL_SH" install --only "gpgkeys"
  assert_success
  refute_output --partial "is not in your PATH"
}

# ── Uninstall ──

@test "uninstall --all removes all installed scripts" {
  "$INSTALL_SH" install --all
  run "$INSTALL_SH" uninstall --all
  assert_success
  assert_output --partial "Removed 6 script(s)"
  for name in gpgkeys sshkeys homebackup sortdownloads imgstotxt pdftoimgs; do
    assert [ ! -f "$INSTALL_DIR/$name" ]
  done
}

@test "uninstall --only removes specific scripts" {
  "$INSTALL_SH" install --all
  run "$INSTALL_SH" uninstall --only "gpgkeys sshkeys"
  assert_success
  assert_output --partial "Removed: gpgkeys"
  assert_output --partial "Removed: sshkeys"
  assert [ ! -f "$INSTALL_DIR/gpgkeys" ]
  assert [ ! -f "$INSTALL_DIR/sshkeys" ]
  # Others remain
  assert [ -f "$INSTALL_DIR/homebackup" ]
}

@test "uninstall with nothing installed shows message" {
  run "$INSTALL_SH" uninstall
  assert_success
  assert_output --partial "No scripts to remove"
}

@test "uninstall does not touch unknown files" {
  "$INSTALL_SH" install --all
  printf "custom\n" > "$INSTALL_DIR/my-custom-script"
  run "$INSTALL_SH" uninstall --all
  assert_success
  assert [ -f "$INSTALL_DIR/my-custom-script" ]
  rm -f "$INSTALL_DIR/my-custom-script"
}

# ── Update ──

@test "update re-downloads changed scripts" {
  "$INSTALL_SH" install --only "gpgkeys sshkeys"
  # Modify the installed script to change its checksum
  printf "old content\n" > "$INSTALL_DIR/gpgkeys"
  # Clear meta for gpgkeys so it doesn't match
  sed -i '/^gpgkeys|/d' "$INSTALL_DIR/.scripts-meta"
  run "$INSTALL_SH" update
  assert_success
  assert_output --partial "Updated: gpgkeys"
  # sshkeys should be up to date (unchanged)
  assert_output --partial "sshkeys: up to date"
  # Verify content was re-downloaded (not "old content")
  run cat "$INSTALL_DIR/gpgkeys"
  refute_output --partial "old content"
}

@test "update only checks installed scripts" {
  "$INSTALL_SH" install --only "gpgkeys"
  run "$INSTALL_SH" update
  assert_success
  assert_output --partial "1 script(s) already up to date"
  assert [ ! -f "$INSTALL_DIR/sshkeys" ]
}

@test "update with nothing installed shows message" {
  run "$INSTALL_SH" update
  assert_success
  assert_output --partial "No scripts currently installed"
}

@test "update --dir uses custom directory" {
  custom_dir="$(mktemp -d)"
  "$INSTALL_SH" install --only "gpgkeys" --dir "$custom_dir"
  run "$INSTALL_SH" update --dir "$custom_dir"
  assert_success
  assert_output --partial "1 script(s) already up to date"
  rm -rf "$custom_dir"
}

# ── Download errors ──

@test "install fails on invalid download URL" {
  export SCRIPTS_REPO_URL="file:///nonexistent/path"
  run "$INSTALL_SH" install --only "gpgkeys"
  assert_failure
  assert_output --partial "Failed to download"
}

# ── Default dispatch ──

@test "no subcommand defaults to install" {
  run "$INSTALL_SH" --all
  assert_success
  assert_output --partial "Installed 6 script(s)"
}

@test "--only without subcommand defaults to install" {
  run "$INSTALL_SH" --only "gpgkeys"
  assert_success
  assert_output --partial "Installed: gpgkeys (1.0.0)"
}

# ── Binary scripts ──

@test "install --only binary script installs binary" {
  run "$INSTALL_SH" install --only "imgstotxt"
  assert_success
  assert_output --partial "Installed: imgstotxt (1.0.0)"
  assert [ -f "$INSTALL_DIR/imgstotxt" ]
  assert [ -x "$INSTALL_DIR/imgstotxt" ]
}

@test "install fails on invalid binary download URL" {
  export RELEASES_BASE_URL="file:///nonexistent/path"
  run "$INSTALL_SH" install --only "pdftoimgs"
  assert_failure
  assert_output --partial "Failed to download"
}

# ── Metadata ──

@test "install stores metadata in .scripts-meta" {
  run "$INSTALL_SH" install --only "gpgkeys"
  assert_success
  assert [ -f "$INSTALL_DIR/.scripts-meta" ]
  run grep "^gpgkeys|" "$INSTALL_DIR/.scripts-meta"
  assert_success
  assert_output --partial "gpgkeys|1.0.0|"
}

@test "install --all stores metadata for all scripts" {
  run "$INSTALL_SH" install --all
  assert_success
  for name in gpgkeys sshkeys homebackup sortdownloads imgstotxt pdftoimgs; do
    run grep "^${name}|" "$INSTALL_DIR/.scripts-meta"
    assert_success
  done
}

@test "uninstall cleans metadata" {
  "$INSTALL_SH" install --only "gpgkeys sshkeys"
  run grep "^gpgkeys|" "$INSTALL_DIR/.scripts-meta"
  assert_success
  "$INSTALL_SH" uninstall --only "gpgkeys"
  run grep "^gpgkeys|" "$INSTALL_DIR/.scripts-meta"
  assert_failure
  # sshkeys metadata should remain
  run grep "^sshkeys|" "$INSTALL_DIR/.scripts-meta"
  assert_success
}

# ── Smart update ──

@test "update skips up-to-date scripts" {
  "$INSTALL_SH" install --only "gpgkeys sshkeys"
  run "$INSTALL_SH" update
  assert_success
  assert_output --partial "gpgkeys: up to date (1.0.0)"
  assert_output --partial "sshkeys: up to date (1.0.0)"
  assert_output --partial "2 script(s) already up to date"
}

@test "update detects changed script" {
  "$INSTALL_SH" install --only "gpgkeys"
  # Change the script in the fake repo
  printf '#!/bin/sh\nVERSION="1.1.0"\necho "updated gpgkeys"\n' > "$FAKE_REPO/shell/gpgkeys.sh"
  run "$INSTALL_SH" update
  assert_success
  assert_output --partial "Updated: gpgkeys"
}

@test "update shows version transition" {
  "$INSTALL_SH" install --only "gpgkeys"
  # Change version in the fake repo
  printf '#!/bin/sh\nVERSION="1.1.0"\necho "gpgkeys.sh"\n' > "$FAKE_REPO/shell/gpgkeys.sh"
  run "$INSTALL_SH" update
  assert_success
  assert_output --partial "1.0.0 → 1.1.0"
}
