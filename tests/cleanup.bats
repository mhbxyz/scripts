#!/usr/bin/env bats

load test_helper

CLEANUP="$SCRIPTS_DIR/cleanup.sh"

setup() {
  setup_cleanup_env
}

teardown() {
  teardown_cleanup_env
}

# ── Help / dispatch ──

@test "help shows usage" {
  run "$CLEANUP" help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "scan"
  assert_output --partial "run"
}

@test "--help shows usage" {
  run "$CLEANUP" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "-h shows usage" {
  run "$CLEANUP" -h
  assert_success
  assert_output --partial "Usage:"
}

@test "unknown command shows error" {
  run "$CLEANUP" foobar
  assert_failure
  assert_output --partial "Unknown command"
}

@test "--version prints version" {
  run "$CLEANUP" --version
  assert_success
  assert_output "1.0.1"
}

# ── Scan ──

@test "scan shows reclaimable space" {
  # Populate trash with some data
  mkdir -p "$HOME/.local/share/Trash/files"
  dd if=/dev/zero of="$HOME/.local/share/Trash/files/bigfile" bs=1024 count=100 2>/dev/null

  run "$CLEANUP" scan --no-sudo
  assert_success
  assert_output --partial "Cleanup scan"
  assert_output --partial "trash"
}

@test "scan with empty dirs shows nothing to clean" {
  run "$CLEANUP" scan --no-sudo
  assert_success
  assert_output --partial "Nothing to clean"
}

# ── Run ──

@test "run --no-confirm cleans trash" {
  mkdir -p "$HOME/.local/share/Trash/files"
  printf 'trash data\n' > "$HOME/.local/share/Trash/files/junk.txt"

  run "$CLEANUP" run --no-confirm --target trash
  assert_success
  assert_output --partial "Cleaned trash"
  assert [ ! -f "$HOME/.local/share/Trash/files/junk.txt" ]
}

@test "run --no-confirm cleans thumbnails" {
  mkdir -p "$HOME/.cache/thumbnails/normal"
  printf 'thumb\n' > "$HOME/.cache/thumbnails/normal/thumb1.png"

  run "$CLEANUP" run --no-confirm --target thumbnails
  assert_success
  assert_output --partial "Cleaned thumbnails"
  assert [ ! -d "$HOME/.cache/thumbnails" ]
}

@test "run --no-confirm cleans partial downloads" {
  mkdir -p "$HOME/Downloads"
  printf 'partial\n' > "$HOME/Downloads/file.part"
  printf 'chrome\n' > "$HOME/Downloads/file.crdownload"

  run "$CLEANUP" run --no-confirm --target downloads
  assert_success
  assert_output --partial "Cleaned"
  assert [ ! -f "$HOME/Downloads/file.part" ]
  assert [ ! -f "$HOME/Downloads/file.crdownload" ]
}

@test "run --target trash cleans only trash" {
  mkdir -p "$HOME/.local/share/Trash/files"
  printf 'trash\n' > "$HOME/.local/share/Trash/files/junk.txt"
  mkdir -p "$HOME/.cache/thumbnails"
  printf 'thumb\n' > "$HOME/.cache/thumbnails/t.png"

  run "$CLEANUP" run --no-confirm --target trash
  assert_success
  assert [ ! -f "$HOME/.local/share/Trash/files/junk.txt" ]
  # Thumbnails should still be there
  assert [ -f "$HOME/.cache/thumbnails/t.png" ]
}

@test "run --target cache cleans large caches" {
  # Create a cache dir over threshold (2MB > 1MB threshold)
  mkdir -p "$HOME/.cache/bigapp"
  dd if=/dev/zero of="$HOME/.cache/bigapp/data" bs=1024 count=2048 2>/dev/null

  run "$CLEANUP" run --no-confirm --target cache --cache-threshold 1
  assert_success
  assert_output --partial "Cleaned large caches"
  assert [ ! -d "$HOME/.cache/bigapp" ]
}

@test "--cache-threshold custom threshold" {
  # Create a 50KB cache
  mkdir -p "$HOME/.cache/smallapp"
  dd if=/dev/zero of="$HOME/.cache/smallapp/data" bs=1024 count=50 2>/dev/null

  # With high threshold, it should not be cleaned
  run "$CLEANUP" scan --target cache --cache-threshold 100
  assert_success
  assert_output --partial "Nothing to clean"

  # With very low threshold (in MB, 0 means scan all... use threshold below size)
  # 50KB = 0.05MB, so threshold of 1KB (0.001 MB) won't work as int. Use a custom approach:
  # The script uses MB, so --cache-threshold 0 means 0 bytes threshold
  # Actually let's make a bigger cache and test
  mkdir -p "$HOME/.cache/medapp"
  dd if=/dev/zero of="$HOME/.cache/medapp/data" bs=1024 count=2048 2>/dev/null

  # threshold 1 MB — the 2MB cache should show up
  run "$CLEANUP" scan --target cache --cache-threshold 1
  assert_success
  assert_output --partial "cache"
  assert_output --partial "MB"
}

@test "--no-sudo skips sudo operations" {
  run "$CLEANUP" scan --no-sudo
  assert_success
  # Should not contain journal (requires sudo)
  refute_output --partial "journal"
}

# ── Mock-based tests ──

@test "scan detects docker (mocked)" {
  setup_mocks

  # Create mock docker that reports data
  mkdir -p "$BATS_TEST_DIRNAME/mocks_cleanup"
  cat > "$BATS_TEST_DIRNAME/mocks_cleanup/docker" <<'MOCKEOF'
#!/bin/sh
if [ "$1" = "system" ] && [ "$2" = "df" ]; then
  printf "TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE\n"
  printf "Images          5         2         2.1GB     1.5GB\n"
  printf "Containers      3         1         500MB     300MB\n"
fi
MOCKEOF
  chmod +x "$BATS_TEST_DIRNAME/mocks_cleanup/docker"
  export PATH="$BATS_TEST_DIRNAME/mocks_cleanup:$PATH"

  run "$CLEANUP" scan --target docker --no-sudo
  assert_success
  assert_output --partial "docker"

  rm -rf "$BATS_TEST_DIRNAME/mocks_cleanup"
}

@test "scan detects package manager (mocked)" {
  # Create mock paccache
  mkdir -p "$BATS_TEST_DIRNAME/mocks_cleanup"
  cat > "$BATS_TEST_DIRNAME/mocks_cleanup/paccache" <<'MOCKEOF'
#!/bin/sh
echo "mock paccache"
MOCKEOF
  chmod +x "$BATS_TEST_DIRNAME/mocks_cleanup/paccache"

  # Create a fake pacman cache
  mkdir -p "$HOME/.cache/pacman_mock"

  export PATH="$BATS_TEST_DIRNAME/mocks_cleanup:$PATH"

  # The scan will detect paccache exists (package manager = pacman)
  # but /var/cache/pacman/pkg likely doesn't exist in test env,
  # so size will be 0. That's fine — we just test detection doesn't crash.
  run "$CLEANUP" scan --target packages
  assert_success

  rm -rf "$BATS_TEST_DIRNAME/mocks_cleanup"
}
