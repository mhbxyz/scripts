#!/usr/bin/env bats

load test_helper

MKPROJECT="$SCRIPTS_DIR/mkproject.sh"

setup() {
  setup_mkproject_env
}

teardown() {
  teardown_mkproject_env
}

# ── Help / dispatch ──

@test "no args shows help" {
  run "$MKPROJECT"
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "template"
}

@test "help shows usage" {
  run "$MKPROJECT" help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "Templates:"
}

@test "--help shows usage" {
  run "$MKPROJECT" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "-h shows usage" {
  run "$MKPROJECT" -h
  assert_success
  assert_output --partial "Usage:"
}

@test "unknown command shows error" {
  run "$MKPROJECT" foobar
  assert_failure
  assert_output --partial "Unknown command"
}

@test "--version prints version" {
  run "$MKPROJECT" --version
  assert_success
  assert_output "1.0.0"
}

# ── List ──

@test "list shows available templates" {
  run "$MKPROJECT" list
  assert_success
  assert_output --partial "sh"
  assert_output --partial "python"
  assert_output --partial "go"
  assert_output --partial "web"
  assert_output --partial "generic"
}

# ── Shell template ──

@test "sh template creates shell project structure" {
  cd "$PROJECTS_DIR"
  run "$MKPROJECT" sh myutil
  assert_success
  assert_output --partial "Created project 'myutil'"
  assert_output --partial "template: sh"
  assert_file_exists "$PROJECTS_DIR/myutil/myutil.sh"
  assert_file_exists "$PROJECTS_DIR/myutil/tests/myutil.bats"
  assert_file_exists "$PROJECTS_DIR/myutil/Makefile"
  assert_file_exists "$PROJECTS_DIR/myutil/.gitignore"
  assert_file_exists "$PROJECTS_DIR/myutil/LICENSE"
  assert_file_exists "$PROJECTS_DIR/myutil/README.md"
  # Check script is executable
  assert [ -x "$PROJECTS_DIR/myutil/myutil.sh" ]
}

# ── Python template ──

@test "python template creates python project structure" {
  cd "$PROJECTS_DIR"
  run "$MKPROJECT" python myapp
  assert_success
  assert_output --partial "Created project 'myapp'"
  assert_file_exists "$PROJECTS_DIR/myapp/src/myapp/__init__.py"
  assert_file_exists "$PROJECTS_DIR/myapp/tests/__init__.py"
  assert_file_exists "$PROJECTS_DIR/myapp/pyproject.toml"
  assert_file_exists "$PROJECTS_DIR/myapp/.gitignore"
  assert_file_exists "$PROJECTS_DIR/myapp/LICENSE"
  assert_file_exists "$PROJECTS_DIR/myapp/README.md"
}

# ── Go template ──

@test "go template creates go project structure" {
  cd "$PROJECTS_DIR"
  run "$MKPROJECT" go myapi
  assert_success
  assert_output --partial "Created project 'myapi'"
  assert_file_exists "$PROJECTS_DIR/myapi/main.go"
  assert_file_exists "$PROJECTS_DIR/myapi/go.mod"
  assert_file_exists "$PROJECTS_DIR/myapi/Makefile"
  assert_file_exists "$PROJECTS_DIR/myapi/.gitignore"
  assert_file_exists "$PROJECTS_DIR/myapi/LICENSE"
  assert_file_exists "$PROJECTS_DIR/myapi/README.md"
}

# ── Web template ──

@test "web template creates web project structure" {
  cd "$PROJECTS_DIR"
  run "$MKPROJECT" web mysite
  assert_success
  assert_output --partial "Created project 'mysite'"
  assert_file_exists "$PROJECTS_DIR/mysite/index.html"
  assert_file_exists "$PROJECTS_DIR/mysite/css/style.css"
  assert_file_exists "$PROJECTS_DIR/mysite/js/main.js"
  assert_file_exists "$PROJECTS_DIR/mysite/.gitignore"
  assert_file_exists "$PROJECTS_DIR/mysite/LICENSE"
  assert_file_exists "$PROJECTS_DIR/mysite/README.md"
}

# ── Generic template ──

@test "generic template creates minimal project" {
  cd "$PROJECTS_DIR"
  run "$MKPROJECT" generic myproject
  assert_success
  assert_output --partial "Created project 'myproject'"
  assert_file_exists "$PROJECTS_DIR/myproject/.gitignore"
  assert_file_exists "$PROJECTS_DIR/myproject/LICENSE"
  assert_file_exists "$PROJECTS_DIR/myproject/README.md"
}

# ── Options ──

@test "--no-git skips git init" {
  cd "$PROJECTS_DIR"
  run "$MKPROJECT" generic myproject --no-git
  assert_success
  assert [ ! -d "$PROJECTS_DIR/myproject/.git" ]
}

@test "--no-readme skips README" {
  cd "$PROJECTS_DIR"
  run "$MKPROJECT" generic myproject --no-readme
  assert_success
  assert [ ! -f "$PROJECTS_DIR/myproject/README.md" ]
}

@test "--license Apache-2.0 uses Apache license" {
  cd "$PROJECTS_DIR"
  run "$MKPROJECT" generic myproject --license Apache-2.0 --no-git
  assert_success
  assert_file_exists "$PROJECTS_DIR/myproject/LICENSE"
  run cat "$PROJECTS_DIR/myproject/LICENSE"
  assert_output --partial "Apache License"
}

@test "--license none creates no license file" {
  cd "$PROJECTS_DIR"
  run "$MKPROJECT" generic myproject --license none --no-git
  assert_success
  assert [ ! -f "$PROJECTS_DIR/myproject/LICENSE" ]
}

@test "existing directory fails" {
  cd "$PROJECTS_DIR"
  mkdir -p "$PROJECTS_DIR/myproject"
  run "$MKPROJECT" generic myproject
  assert_failure
  assert_output --partial "already exists"
}

@test "unknown template fails" {
  cd "$PROJECTS_DIR"
  run "$MKPROJECT" java myproject
  assert_failure
  assert_output --partial "Unknown command"
}
