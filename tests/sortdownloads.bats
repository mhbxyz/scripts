#!/usr/bin/env bats

load test_helper

SORTDOWNLOADS="$SCRIPTS_DIR/sortdownloads.sh"

setup() {
  setup_sortdownloads_env
  setup_mocks
}

teardown() {
  teardown_sortdownloads_env
}

# ── Help / dispatch ──

@test "no arguments shows help" {
  run "$SORTDOWNLOADS"
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "Commands:"
}

@test "help command shows help" {
  run "$SORTDOWNLOADS" help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "now"
  assert_output --partial "schedule"
}

@test "--help shows help" {
  run "$SORTDOWNLOADS" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "-h shows help" {
  run "$SORTDOWNLOADS" -h
  assert_success
  assert_output --partial "Usage:"
}

@test "unknown command shows error" {
  run "$SORTDOWNLOADS" foobar
  assert_success
  assert_output --partial "Unknown command: foobar"
  assert_output --partial "Usage:"
}

# ── Argument validation ──

@test "now with unknown flag fails" {
  run "$SORTDOWNLOADS" now --bogus
  assert_failure
  assert_output --partial "Unknown option: --bogus"
}

@test "schedule without frequency fails" {
  run "$SORTDOWNLOADS" schedule
  assert_failure
  assert_output --partial "Missing frequency"
}

@test "schedule with invalid frequency fails" {
  run "$SORTDOWNLOADS" schedule hourly
  assert_failure
  assert_output --partial "Invalid frequency"
}

@test "--on and --start are mutually exclusive" {
  run "$SORTDOWNLOADS" schedule weekly --on mon --start
  assert_failure
  assert_output --partial "mutually exclusive"
}

@test "--at with invalid time fails" {
  run "$SORTDOWNLOADS" schedule daily --at 25:99
  assert_failure
  assert_output --partial "Invalid"
}

# ── Sorting (cmd_now) ──

@test "pdf sorted to Documents/PDFs" {
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert_file_exists "$DOWNLOADS/Documents/PDFs/report.pdf"
}

@test "jpg sorted to Images/JPG" {
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert_file_exists "$DOWNLOADS/Images/JPG/photo.jpg"
}

@test "mp4 sorted to Videos/MP4" {
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert_file_exists "$DOWNLOADS/Videos/MP4/video.mp4"
}

@test "mp3 sorted to Music/MP3" {
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert_file_exists "$DOWNLOADS/Music/MP3/song.mp3"
}

@test "zip sorted to Archives/ZIP" {
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert_file_exists "$DOWNLOADS/Archives/ZIP/archive.zip"
}

@test "deb sorted to Programs/DEB" {
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert_file_exists "$DOWNLOADS/Programs/DEB/installer.deb"
}

@test "sh sorted to Scripts/Shell" {
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert_file_exists "$DOWNLOADS/Scripts/Shell/script.sh"
}

@test "ttf sorted to Fonts" {
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert_file_exists "$DOWNLOADS/Fonts/font.ttf"
}

@test "iso sorted to Disk Images/ISO" {
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert_file_exists "$DOWNLOADS/Disk Images/ISO/image.iso"
}

@test "json sorted to Documents/Data" {
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert_file_exists "$DOWNLOADS/Documents/Data/data.json"
}

@test "file without extension sorted to Other" {
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert_file_exists "$DOWNLOADS/Other/noextension"
}

# ── Edge cases ──

@test "hidden files are skipped" {
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert_file_exists "$DOWNLOADS/.hidden_file"
}

@test "symlinks are skipped" {
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert [ -L "$DOWNLOADS/symlink.pdf" ]
}

@test "directories are skipped" {
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert [ -d "$DOWNLOADS/subdirectory" ]
}

@test ".part files are skipped" {
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert_file_exists "$DOWNLOADS/downloading.part"
}

@test ".crdownload files are skipped" {
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert_file_exists "$DOWNLOADS/inprogress.crdownload"
}

@test "empty folder shows info message" {
  rm -rf "$DOWNLOADS"/*
  rm -f "$DOWNLOADS"/.hidden_file
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert_output --partial "empty"
}

@test "duplicates get numbered suffix" {
  mkdir -p "$DOWNLOADS/Documents/PDFs"
  printf "existing" > "$DOWNLOADS/Documents/PDFs/report.pdf"
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert_file_exists "$DOWNLOADS/Documents/PDFs/report (1).pdf"
}

# ── Dry run ──

@test "dry-run does not move files" {
  run "$SORTDOWNLOADS" now --dry-run --dir "$DOWNLOADS"
  assert_success
  assert_output --partial "Dry run"
  # Original files should still be in place
  assert_file_exists "$DOWNLOADS/report.pdf"
  assert_file_exists "$DOWNLOADS/photo.jpg"
}

@test "dry-run shows planned actions" {
  run "$SORTDOWNLOADS" now --dry-run --dir "$DOWNLOADS"
  assert_success
  assert_output --partial "report.pdf"
  assert_output --partial "Documents/PDFs/"
}

# ── Verbose ──

@test "verbose shows each move" {
  run "$SORTDOWNLOADS" now --verbose --dir "$DOWNLOADS"
  assert_success
  assert_output --partial "report.pdf"
  assert_output --partial "photo.jpg"
}

# ── Locale FR ──

@test "french locale translates main categories" {
  export LANG="fr_FR.UTF-8"
  export LC_ALL="fr_FR.UTF-8"
  run "$SORTDOWNLOADS" now --dir "$DOWNLOADS"
  assert_success
  assert_file_exists "$DOWNLOADS/Vidéos/MP4/video.mp4"
  assert_file_exists "$DOWNLOADS/Musique/MP3/song.mp3"
  assert_file_exists "$DOWNLOADS/Programmes/DEB/installer.deb"
  assert_file_exists "$DOWNLOADS/Polices/font.ttf"
  assert_file_exists "$DOWNLOADS/Images disque/ISO/image.iso"
  assert_file_exists "$DOWNLOADS/Autres/noextension"
}

# ── Scheduling ──

@test "schedule daily installs systemd timer" {
  run "$SORTDOWNLOADS" schedule daily --at 08:00
  assert_success
  assert_output --partial "Installed systemd timer: *-*-* 08:00:00"
  # Verify mock received the right commands
  assert_file_exists "$SORTDOWNLOADS_MOCK_DIR/calls"
  run cat "$SORTDOWNLOADS_MOCK_DIR/calls"
  assert_output --partial "daemon-reload"
  assert_output --partial "enable"
}

@test "schedule weekly --start defaults to Mon" {
  run "$SORTDOWNLOADS" schedule weekly --start --at 10:00
  assert_success
  assert_output --partial "Installed systemd timer: Mon *-*-* 10:00:00"
}

@test "schedule weekly --end defaults to Sun" {
  run "$SORTDOWNLOADS" schedule weekly --end --at 10:00
  assert_success
  assert_output --partial "Installed systemd timer: Sun *-*-* 10:00:00"
}

@test "schedule monthly --end defaults to 28" {
  run "$SORTDOWNLOADS" schedule monthly --end --at 10:00
  assert_success
  assert_output --partial "Installed systemd timer: *-*-28 10:00:00"
}

@test "unschedule removes systemd timer" {
  # First install
  run "$SORTDOWNLOADS" schedule daily
  assert_success
  # Mark as enabled for mock
  touch "$SORTDOWNLOADS_MOCK_DIR/timer-enabled"
  # Then unschedule
  run "$SORTDOWNLOADS" unschedule
  assert_success
  assert_output --partial "Removed systemd timer"
  # Verify mock received disable command
  run cat "$SORTDOWNLOADS_MOCK_DIR/calls"
  assert_output --partial "disable"
}
