#!/usr/bin/env bats

load test_helper

DOTFILES="$SCRIPTS_DIR/dotfiles.sh"

setup() {
  setup_dotfiles_env
}

teardown() {
  teardown_dotfiles_env
}

# ── Help / dispatch ──

@test "no args shows help" {
  run "$DOTFILES"
  assert_success
  assert_output --partial "Usage:"
}

@test "help shows usage" {
  run "$DOTFILES" help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "Commands:"
}

@test "--help shows usage" {
  run "$DOTFILES" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "-h shows usage" {
  run "$DOTFILES" -h
  assert_success
  assert_output --partial "Usage:"
}

@test "unknown command shows error" {
  run "$DOTFILES" foobar
  assert_failure
  assert_output --partial "Unknown command"
}

@test "--version prints version" {
  run "$DOTFILES" --version
  assert_success
  assert_output "1.0.1"
}

# ── Init ──

@test "init creates dotfiles dir + mapping.conf" {
  run "$DOTFILES" init --dir "$DOTFILES_DIR"
  assert_success
  assert_file_exists "$DOTFILES_DIR/mapping.conf"
  assert [ -d "$DOTFILES_DIR/.backup" ]
}

@test "init --dir creates custom directory" {
  _custom="$DOTFILES_DIR-custom"
  run "$DOTFILES" init --dir "$_custom"
  assert_success
  assert_file_exists "$_custom/mapping.conf"
  assert [ -d "$_custom/.backup" ]
  rm -rf "$_custom"
}

@test "init fails if exists" {
  "$DOTFILES" init --dir "$DOTFILES_DIR"
  run "$DOTFILES" init --dir "$DOTFILES_DIR"
  assert_failure
  assert_output --partial "already exists"
}

# ── Add ──

@test "add moves file + creates symlink + updates mapping" {
  "$DOTFILES" init --dir "$DOTFILES_DIR"
  run "$DOTFILES" add "$HOME/.bashrc" --dir "$DOTFILES_DIR"
  assert_success
  # File moved to dotfiles dir
  assert_file_exists "$DOTFILES_DIR/bashrc"
  # Symlink created
  assert [ -L "$HOME/.bashrc" ]
  # Mapping updated
  run grep "bashrc:" "$DOTFILES_DIR/mapping.conf"
  assert_success
}

@test "add directory handles directories" {
  "$DOTFILES" init --dir "$DOTFILES_DIR"
  run "$DOTFILES" add "$HOME/.config/nvim" --dir "$DOTFILES_DIR" --name nvim
  assert_success
  assert [ -d "$DOTFILES_DIR/nvim" ]
  assert [ -L "$HOME/.config/nvim" ]
  run grep "nvim:" "$DOTFILES_DIR/mapping.conf"
  assert_success
}

# ── Link ──

@test "link creates all symlinks" {
  "$DOTFILES" init --dir "$DOTFILES_DIR"
  # Manually set up mapping and dotfiles content
  printf 'file_a content\n' > "$DOTFILES_DIR/file_a"
  printf 'file_b content\n' > "$DOTFILES_DIR/file_b"
  printf 'file_a:%s/.file_a\nfile_b:%s/.file_b\n' "$HOME" "$HOME" >> "$DOTFILES_DIR/mapping.conf"

  run "$DOTFILES" link --dir "$DOTFILES_DIR"
  assert_success
  assert [ -L "$HOME/.file_a" ]
  assert [ -L "$HOME/.file_b" ]
}

@test "link --dry-run shows without executing" {
  "$DOTFILES" init --dir "$DOTFILES_DIR"
  printf 'content\n' > "$DOTFILES_DIR/testfile"
  printf 'testfile:%s/.testfile\n' "$HOME" >> "$DOTFILES_DIR/mapping.conf"

  run "$DOTFILES" link --dir "$DOTFILES_DIR" --dry-run
  assert_success
  assert_output --partial "Would link"
  assert [ ! -L "$HOME/.testfile" ]
}

@test "link single links one file" {
  "$DOTFILES" init --dir "$DOTFILES_DIR"
  printf 'a\n' > "$DOTFILES_DIR/file_a"
  printf 'b\n' > "$DOTFILES_DIR/file_b"
  printf 'file_a:%s/.file_a\nfile_b:%s/.file_b\n' "$HOME" "$HOME" >> "$DOTFILES_DIR/mapping.conf"

  run "$DOTFILES" link --dir "$DOTFILES_DIR" file_a
  assert_success
  assert [ -L "$HOME/.file_a" ]
  assert [ ! -L "$HOME/.file_b" ]
}

# ── Unlink ──

@test "unlink removes symlinks" {
  "$DOTFILES" init --dir "$DOTFILES_DIR"
  printf 'content\n' > "$DOTFILES_DIR/testfile"
  printf 'testfile:%s/.testfile\n' "$HOME" >> "$DOTFILES_DIR/mapping.conf"
  "$DOTFILES" link --dir "$DOTFILES_DIR"
  assert [ -L "$HOME/.testfile" ]

  run "$DOTFILES" unlink --dir "$DOTFILES_DIR"
  assert_success
  assert [ ! -L "$HOME/.testfile" ]
}

@test "unlink restores backup" {
  "$DOTFILES" init --dir "$DOTFILES_DIR"
  # Create a backup
  printf 'backup content\n' > "$DOTFILES_DIR/.backup/.testfile"
  printf 'repo content\n' > "$DOTFILES_DIR/testfile"
  printf 'testfile:%s/.testfile\n' "$HOME" >> "$DOTFILES_DIR/mapping.conf"
  "$DOTFILES" link --dir "$DOTFILES_DIR"
  assert [ -L "$HOME/.testfile" ]

  run "$DOTFILES" unlink --dir "$DOTFILES_DIR"
  assert_success
  assert [ ! -L "$HOME/.testfile" ]
  assert [ -f "$HOME/.testfile" ]
  run cat "$HOME/.testfile"
  assert_output "backup content"
}

# ── Status ──

@test "status shows linked/unlinked/conflict" {
  "$DOTFILES" init --dir "$DOTFILES_DIR"
  printf 'a\n' > "$DOTFILES_DIR/file_linked"
  printf 'b\n' > "$DOTFILES_DIR/file_unlinked"
  printf 'c\n' > "$DOTFILES_DIR/file_conflict"
  printf 'file_linked:%s/.file_linked\n' "$HOME" >> "$DOTFILES_DIR/mapping.conf"
  printf 'file_unlinked:%s/.file_unlinked\n' "$HOME" >> "$DOTFILES_DIR/mapping.conf"
  printf 'file_conflict:%s/.file_conflict\n' "$HOME" >> "$DOTFILES_DIR/mapping.conf"

  # Create linked symlink
  ln -s "$DOTFILES_DIR/file_linked" "$HOME/.file_linked"
  # Create conflict (regular file)
  printf 'conflict\n' > "$HOME/.file_conflict"

  run "$DOTFILES" status --dir "$DOTFILES_DIR"
  assert_success
  assert_output --partial "linked"
  assert_output --partial "not linked"
  assert_output --partial "conflict"
}

# ── List ──

@test "list shows mapping entries" {
  "$DOTFILES" init --dir "$DOTFILES_DIR"
  printf 'bashrc:%s/.bashrc\n' '$HOME' >> "$DOTFILES_DIR/mapping.conf"
  printf 'gitconfig:%s/.gitconfig\n' '$HOME' >> "$DOTFILES_DIR/mapping.conf"

  run "$DOTFILES" list --dir "$DOTFILES_DIR"
  assert_success
  assert_output --partial "bashrc"
  assert_output --partial "gitconfig"
}

# ── Remove ──

@test "remove removes entry from mapping + unlinks" {
  "$DOTFILES" init --dir "$DOTFILES_DIR"
  printf 'content\n' > "$DOTFILES_DIR/testfile"
  printf 'testfile:%s/.testfile\n' "$HOME" >> "$DOTFILES_DIR/mapping.conf"
  "$DOTFILES" link --dir "$DOTFILES_DIR"
  assert [ -L "$HOME/.testfile" ]

  run "$DOTFILES" remove testfile --dir "$DOTFILES_DIR"
  assert_success
  assert [ ! -L "$HOME/.testfile" ]
  # Mapping should not contain testfile
  run grep "^testfile:" "$DOTFILES_DIR/mapping.conf"
  assert_failure
  # File removed from repo
  assert [ ! -e "$DOTFILES_DIR/testfile" ]
}

# ── Diff ──

@test "diff shows differences" {
  "$DOTFILES" init --dir "$DOTFILES_DIR"
  printf 'repo version\n' > "$DOTFILES_DIR/testfile"
  printf 'testfile:%s/.testfile\n' "$HOME" >> "$DOTFILES_DIR/mapping.conf"
  # Create a different file at target (not a symlink)
  printf 'local version\n' > "$HOME/.testfile"

  run "$DOTFILES" diff --dir "$DOTFILES_DIR"
  assert_success
  assert_output --partial "testfile"
  assert_output --partial "repo version"
  assert_output --partial "local version"
}
