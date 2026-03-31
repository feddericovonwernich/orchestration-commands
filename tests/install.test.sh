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
  if [[ ! -f "$file" ]]; then
    printf 'FAIL: expected file to exist: %s\n' "$file" >&2
    exit 1
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
}

assert_no_files_match() {
  local pattern="$1"
  shopt -s nullglob
  local matches=($pattern)
  shopt -u nullglob

  if [[ ${#matches[@]} -ne 0 ]]; then
    printf 'FAIL: expected no files matching %s\n' "$pattern" >&2
    printf 'Found: %s\n' "${matches[*]}" >&2
    exit 1
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
}

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq -- "$expected" "$file"; then
    printf 'FAIL: expected text not found in %s\n' "$file" >&2
    printf 'Expected: %s\n' "$expected" >&2
    exit 1
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
}

assert_not_contains() {
  local file="$1"
  local forbidden="$2"
  if grep -Fq -- "$forbidden" "$file"; then
    printf 'FAIL: forbidden text found in %s\n' "$file" >&2
    printf 'Forbidden: %s\n' "$forbidden" >&2
    exit 1
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
}

assert_files_equal() {
  local left="$1"
  local right="$2"
  if ! cmp -s "$left" "$right"; then
    printf 'FAIL: files differ:\n  %s\n  %s\n' "$left" "$right" >&2
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

# Case 1: default install output matches local source files.
case1_dir="$TMP_ROOT/case1-project"
mkdir -p "$case1_dir"
run_install "$ROOT_DIR" "$ROOT_DIR/install.sh" --scope project --path "$case1_dir"

assert_files_equal "$case1_dir/.opencode/agents/orchestrator-loop.md" "$ROOT_DIR/.opencode/agents/orchestrator-loop.md"
assert_files_equal "$case1_dir/.opencode/agents/impl-worker.md" "$ROOT_DIR/.opencode/agents/impl-worker.md"
assert_files_equal "$case1_dir/.opencode/agents/reviewer.md" "$ROOT_DIR/.opencode/agents/reviewer.md"
assert_files_equal "$case1_dir/.opencode/commands/orchestrate.md" "$ROOT_DIR/.opencode/commands/orchestrate.md"

# Case 2: custom --max-loops rewrites loop count placeholders.
case2_dir="$TMP_ROOT/case2-project"
mkdir -p "$case2_dir"
run_install "$ROOT_DIR" "$ROOT_DIR/install.sh" --scope project --path "$case2_dir" --max-loops 7

assert_contains "$case2_dir/.opencode/agents/orchestrator-loop.md" '- Max loops: 7'
assert_contains "$case2_dir/.opencode/agents/orchestrator-loop.md" '- Max loops: 7 (per phase cap)'
assert_contains "$case2_dir/.opencode/agents/orchestrator-loop.md" '- LOOPS_USED: n/7'
assert_contains "$case2_dir/.opencode/commands/orchestrate.md" 'max loops 7'
assert_not_contains "$case2_dir/.opencode/agents/orchestrator-loop.md" '- Max loops: 3'

# Case 3: reinstall creates backups by default.
case3_dir="$TMP_ROOT/case3-project"
case3_backup_dir="$case3_dir/.opencode-install-backups"
mkdir -p "$case3_dir"
run_install "$ROOT_DIR" "$ROOT_DIR/install.sh" --scope project --path "$case3_dir"
printf '# user edit\n' >>"$case3_dir/.opencode/agents/reviewer.md"
run_install "$ROOT_DIR" "$ROOT_DIR/install.sh" --scope project --path "$case3_dir"

shopt -s nullglob
case3_backups=("$case3_backup_dir/agents/reviewer.md.bak."*)
shopt -u nullglob
if [[ ${#case3_backups[@]} -lt 1 ]]; then
  printf 'FAIL: expected backup reviewer file on reinstall\n' >&2
  exit 1
fi
PASS_COUNT=$((PASS_COUNT + 1))
assert_no_files_match "$case3_dir/.opencode/agents/reviewer.md.bak.*"
assert_not_contains "$case3_dir/.opencode/agents/reviewer.md" '# user edit'

# Case 4: --force overwrites without backups.
case4_dir="$TMP_ROOT/case4-project"
case4_backup_dir="$case4_dir/.opencode-install-backups"
mkdir -p "$case4_dir"
run_install "$ROOT_DIR" "$ROOT_DIR/install.sh" --scope project --path "$case4_dir"
printf '# local tweak\n' >>"$case4_dir/.opencode/agents/reviewer.md"
run_install "$ROOT_DIR" "$ROOT_DIR/install.sh" --scope project --path "$case4_dir" --force

assert_no_files_match "$case4_dir/.opencode/agents/reviewer.md.bak.*"
assert_no_files_match "$case4_backup_dir/agents/reviewer.md.bak.*"
assert_not_contains "$case4_dir/.opencode/agents/reviewer.md" '# local tweak'

# Case 5: fallback source works when script has no local .opencode directory.
case5_dir="$TMP_ROOT/case5-project"
case5_runner="$TMP_ROOT/fallback-runner"
mkdir -p "$case5_dir" "$case5_runner"
cp "$ROOT_DIR/install.sh" "$case5_runner/install.sh"
chmod +x "$case5_runner/install.sh"

(cd "$case5_runner" && ORCHESTRATION_COMMANDS_SOURCE_BASE_URL="file://$ROOT_DIR/.opencode" bash "$case5_runner/install.sh" --scope project --path "$case5_dir")

assert_files_equal "$case5_dir/.opencode/agents/orchestrator-loop.md" "$ROOT_DIR/.opencode/agents/orchestrator-loop.md"
assert_files_equal "$case5_dir/.opencode/agents/impl-worker.md" "$ROOT_DIR/.opencode/agents/impl-worker.md"
assert_files_equal "$case5_dir/.opencode/agents/reviewer.md" "$ROOT_DIR/.opencode/agents/reviewer.md"
assert_files_equal "$case5_dir/.opencode/commands/orchestrate.md" "$ROOT_DIR/.opencode/commands/orchestrate.md"

printf 'PASS: %d installer checks\n' "$PASS_COUNT"
