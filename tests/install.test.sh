#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
PASS_COUNT=0

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

assert_file_exists() {
  local file="$1"
  if [[ ! -f "$file" && ! -L "$file" ]]; then
    printf 'FAIL: expected file to exist: %s\n' "$file" >&2
    exit 1
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
}

assert_is_symlink_to() {
  local link_path="$1"
  local expected_target="$2"

  if [[ ! -L "$link_path" ]]; then
    printf 'FAIL: expected symlink: %s\n' "$link_path" >&2
    exit 1
  fi

  local actual_target
  actual_target="$(readlink "$link_path")"
  if [[ "$actual_target" != "$expected_target" ]]; then
    printf 'FAIL: symlink target mismatch for %s\n' "$link_path" >&2
    printf 'Expected: %s\n' "$expected_target" >&2
    printf 'Actual:   %s\n' "$actual_target" >&2
    exit 1
  fi

  PASS_COUNT=$((PASS_COUNT + 1))
}

assert_path_missing() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    printf 'FAIL: expected path to be missing: %s\n' "$path" >&2
    exit 1
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
}

assert_command_fails() {
  local cwd="$1"
  shift
  if (cd "$cwd" && bash "$@" >/dev/null 2>&1); then
    printf 'FAIL: expected command to fail: %s\n' "$*" >&2
    exit 1
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
}

run_install() {
  local cwd="$1"
  shift
  (cd "$cwd" && bash "$@")
}

printf 'Running installer regression tests ...\n'

SOURCE_ORCHESTRATOR="$ROOT_DIR/.opencode/agents/orchestrator-loop.md"
SOURCE_IMPL="$ROOT_DIR/.opencode/agents/impl-worker.md"
SOURCE_REVIEWER="$ROOT_DIR/.opencode/agents/reviewer.md"
SOURCE_COMMAND="$ROOT_DIR/.opencode/commands/orchestrate.md"

# Case 1: project install creates symlinks to clone source.
case1_dir="$TMP_ROOT/case1-project"
mkdir -p "$case1_dir"
run_install "$ROOT_DIR" "$ROOT_DIR/install.sh" --scope project --path "$case1_dir" --clone-dir "$ROOT_DIR"

assert_file_exists "$case1_dir/.opencode/agents/orchestrator-loop.md"
assert_file_exists "$case1_dir/.opencode/agents/impl-worker.md"
assert_file_exists "$case1_dir/.opencode/agents/reviewer.md"
assert_file_exists "$case1_dir/.opencode/commands/orchestrate.md"

assert_is_symlink_to "$case1_dir/.opencode/agents/orchestrator-loop.md" "$SOURCE_ORCHESTRATOR"
assert_is_symlink_to "$case1_dir/.opencode/agents/impl-worker.md" "$SOURCE_IMPL"
assert_is_symlink_to "$case1_dir/.opencode/agents/reviewer.md" "$SOURCE_REVIEWER"
assert_is_symlink_to "$case1_dir/.opencode/commands/orchestrate.md" "$SOURCE_COMMAND"

# Case 2: install fails when target exists and is not the expected link.
case2_dir="$TMP_ROOT/case2-project"
mkdir -p "$case2_dir"
run_install "$ROOT_DIR" "$ROOT_DIR/install.sh" --scope project --path "$case2_dir" --clone-dir "$ROOT_DIR"
rm -f "$case2_dir/.opencode/agents/reviewer.md"
printf 'local file\n' >"$case2_dir/.opencode/agents/reviewer.md"
assert_command_fails "$ROOT_DIR" "$ROOT_DIR/install.sh" --scope project --path "$case2_dir" --clone-dir "$ROOT_DIR"

# Case 3: --force replaces existing non-link targets.
run_install "$ROOT_DIR" "$ROOT_DIR/install.sh" --scope project --path "$case2_dir" --clone-dir "$ROOT_DIR" --force
assert_is_symlink_to "$case2_dir/.opencode/agents/reviewer.md" "$SOURCE_REVIEWER"

# Case 4: --clean removes installation files and backup dir before linking.
case4_dir="$TMP_ROOT/case4-project"
case4_backup_dir="$case4_dir/.opencode-install-backups"
mkdir -p "$case4_dir" "$case4_backup_dir"
printf 'old backup\n' >"$case4_backup_dir/old.txt"
run_install "$ROOT_DIR" "$ROOT_DIR/install.sh" --scope project --path "$case4_dir" --clone-dir "$ROOT_DIR"
run_install "$ROOT_DIR" "$ROOT_DIR/install.sh" --scope project --path "$case4_dir" --clone-dir "$ROOT_DIR" --clean

assert_is_symlink_to "$case4_dir/.opencode/commands/orchestrate.md" "$SOURCE_COMMAND"
assert_path_missing "$case4_backup_dir"

printf 'PASS: %d installer checks\n' "$PASS_COUNT"
