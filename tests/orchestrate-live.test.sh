#!/usr/bin/env bash
set -euo pipefail

if [[ "${OPENCODE_LIVE_TEST:-0}" != "1" ]]; then
  printf 'Skipping /orchestrate live smoke tests. Set OPENCODE_LIVE_TEST=1 to enable.\n'
  exit 0
fi

if ! command -v opencode >/dev/null 2>&1; then
  printf 'FAIL: opencode CLI is not installed or not in PATH.\n' >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMEOUT_SECONDS="${OPENCODE_LIVE_TIMEOUT:-120}"

PASS_COUNT=0

run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$TIMEOUT_SECONDS" "$@"
  else
    "$@"
  fi
}

assert_live_case() {
  local title="$1"
  local regex="$2"
  shift 2

  local output
  local status

  set +e
  output="$(run_with_timeout "$@" 2>&1)"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    printf 'FAIL: %s (exit %d)\n' "$title" "$status" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi

  if ! grep -Eiq -- "$regex" <<<"$output"; then
    printf 'FAIL: %s (expected output to match /%s/)\n' "$title" "$regex" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi

  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS: %s\n' "$title"
}

cd "$ROOT_DIR"

printf 'Running /orchestrate live smoke tests (timeout %ss)...\n' "$TIMEOUT_SECONDS"

assert_live_case \
  'auto mode requests APPROVE gate' \
  'APPROVE|EDIT:' \
  opencode run --command orchestrate "Add optimistic UI updates for comment posting"

assert_live_case \
  'exec mode without plan asks for plan content' \
  'approved plan|full approved plan|plan content' \
  opencode run --command orchestrate exec

assert_live_case \
  'exec mode with --no-commit reflects disabled commits' \
  'no-commit|commit mode|disabled' \
  opencode run --command orchestrate -- --no-commit exec "1. Add a placeholder verification step."

printf 'PASS: %d live smoke checks\n' "$PASS_COUNT"
