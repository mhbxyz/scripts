#!/usr/bin/env bats

load test_helper

HOMEBACKUP="$SCRIPTS_DIR/homebackup.sh"

setup() {
  setup_backup_env
}

teardown() {
  teardown_backup_env
}

# ── Help / dispatch ──

@test "no arguments shows help" {
  run "$HOMEBACKUP"
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "Commands:"
}

@test "help command shows help" {
  run "$HOMEBACKUP" help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "run"
  assert_output --partial "list"
}

@test "--help shows help" {
  run "$HOMEBACKUP" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "-h shows help" {
  run "$HOMEBACKUP" -h
  assert_success
  assert_output --partial "Usage:"
}

@test "unknown command shows error" {
  run "$HOMEBACKUP" foobar
  assert_success
  assert_output --partial "Unknown command: foobar"
  assert_output --partial "Usage:"
}

# ── Argument validation ──

@test "run with unknown flag fails" {
  run "$HOMEBACKUP" run --bogus
  assert_failure
  assert_output --partial "Unknown option: --bogus"
}

@test "run with invalid compress type fails" {
  run "$HOMEBACKUP" run --drive TestDrive --compress lz4
  assert_failure
  assert_output --partial "Invalid compression type"
}

@test "run with nonexistent exclude-file fails" {
  run "$HOMEBACKUP" run --drive TestDrive --exclude-file /nonexistent/file.txt
  assert_failure
  assert_output --partial "Exclude file not found"
}

# ── check_dep ──

@test "missing tar dependency shows error" {
  run env PATH=/usr/bin/nonexistent "$HOMEBACKUP" help
  assert_failure
  assert_output --partial "tar"
  assert_output --partial "required"
}

# ── List ──

@test "list shows drives from fake mount" {
  run "$HOMEBACKUP" list
  assert_success
  assert_output --partial "TestDrive"
}

@test "list with no drives fails" {
  empty_mount=$(mktemp -d)
  export HOMEBACKUP_MOUNT_BASES="$empty_mount"
  run "$HOMEBACKUP" list
  assert_failure
  assert_output --partial "No mounted drives"
  rm -rf "$empty_mount"
}

# ── Drive resolution ──

@test "run --drive resolves valid drive" {
  run "$HOMEBACKUP" run --drive TestDrive --dry-run --default-excludes
  assert_success
  assert_output --partial "Dry run"
}

@test "run --drive with nonexistent drive fails" {
  run "$HOMEBACKUP" run --drive NonExistent --dry-run
  assert_failure
  assert_output --partial "Drive not found"
}

# ── Excludes ──

@test "default-excludes applies default list" {
  run "$HOMEBACKUP" run --drive TestDrive --dry-run --default-excludes
  assert_success
  assert_output --partial "Excluding:"
  assert_output --partial ".cache"
  assert_output --partial ".local"
}

@test "custom excludes replaces defaults" {
  run "$HOMEBACKUP" run --drive TestDrive --dry-run --excludes "Pictures"
  assert_success
  assert_output --partial "- Pictures"
  # .cache was NOT excluded (defaults replaced), so it appears in listing
  assert_output --partial ".cache/cached.tmp"
  # Pictures WAS excluded, so photo.jpg should not appear
  refute_output --partial "photo.jpg"
}

@test "add-excludes adds to default" {
  run "$HOMEBACKUP" run --drive TestDrive --dry-run --default-excludes --add-excludes "Music"
  assert_success
  assert_output --partial ".cache"
  assert_output --partial "Music"
}

@test "exclude-file is used" {
  ef=$(mktemp)
  printf "Pictures\n" > "$ef"
  run "$HOMEBACKUP" run --drive TestDrive --dry-run --exclude-file "$ef"
  assert_success
  assert_output --partial "Pictures"
  rm -f "$ef"
}

# ── Backup end-to-end ──

@test "backup creates .tar.gz with default compression" {
  run "$HOMEBACKUP" run --drive TestDrive --default-excludes
  assert_success
  assert_output --partial "Backup completed"
  # Check archive exists
  count=$(find "$FAKE_DRIVE/backups" -name "home_backup_*.tar.gz" | wc -l)
  [ "$count" -eq 1 ]
}

@test "backup with --compress none creates .tar" {
  run "$HOMEBACKUP" run --drive TestDrive --compress none --default-excludes
  assert_success
  assert_output --partial "Backup completed"
  count=$(find "$FAKE_DRIVE/backups" -name "home_backup_*.tar" ! -name "*.tar.*" | wc -l)
  [ "$count" -eq 1 ]
}

@test "backup archive contains expected files" {
  run "$HOMEBACKUP" run --drive TestDrive --compress none --default-excludes
  assert_success
  archive=$(find "$FAKE_DRIVE/backups" -name "home_backup_*.tar" ! -name "*.tar.*" | head -1)
  run tar -tf "$archive"
  assert_success
  assert_output --partial "Documents/file1.txt"
  assert_output --partial "Pictures/photo.jpg"
  assert_output --partial ".config/settings.conf"
}

@test "default-excludes omits .cache from archive" {
  run "$HOMEBACKUP" run --drive TestDrive --compress none --default-excludes
  assert_success
  archive=$(find "$FAKE_DRIVE/backups" -name "home_backup_*.tar" ! -name "*.tar.*" | head -1)
  run tar -tf "$archive"
  assert_success
  refute_output --partial ".cache/cached.tmp"
}

@test "backup with custom --backup-dir" {
  run "$HOMEBACKUP" run --drive TestDrive --compress none --backup-dir mybackups --default-excludes
  assert_success
  assert_output --partial "Backup completed"
  count=$(find "$FAKE_DRIVE/mybackups" -name "home_backup_*.tar" | wc -l)
  [ "$count" -eq 1 ]
}

# ── Dry run ──

@test "dry-run lists files without creating archive" {
  run "$HOMEBACKUP" run --drive TestDrive --dry-run --default-excludes
  assert_success
  assert_output --partial "Dry run"
  # No archive should be created
  count=$(find "$FAKE_DRIVE" -name "home_backup_*" 2>/dev/null | wc -l)
  [ "$count" -eq 0 ]
}

# ── Verify ──

@test "verify succeeds on valid archive" {
  run "$HOMEBACKUP" run --drive TestDrive --compress none --verify --default-excludes
  assert_success
  assert_output --partial "Verification OK"
}

# ── Compression variants ──

@test "backup with --compress xz creates .tar.xz" {
  if ! command -v xz >/dev/null 2>&1; then
    skip "xz not installed"
  fi
  run "$HOMEBACKUP" run --drive TestDrive --compress xz --default-excludes
  assert_success
  count=$(find "$FAKE_DRIVE/backups" -name "home_backup_*.tar.xz" | wc -l)
  [ "$count" -eq 1 ]
}

@test "backup with --compress zstd creates .tar.zst" {
  if ! command -v zstd >/dev/null 2>&1; then
    skip "zstd not installed"
  fi
  run "$HOMEBACKUP" run --drive TestDrive --compress zstd --default-excludes
  assert_success
  count=$(find "$FAKE_DRIVE/backups" -name "home_backup_*.tar.zst" | wc -l)
  [ "$count" -eq 1 ]
}
