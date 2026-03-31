#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

COMMAND_FILE="$ROOT_DIR/.opencode/commands/orchestrate.md"
ORCHESTRATOR_AGENT="$ROOT_DIR/.opencode/agents/orchestrator-loop.md"
IMPL_AGENT="$ROOT_DIR/.opencode/agents/impl-worker.md"
REVIEWER_AGENT="$ROOT_DIR/.opencode/agents/reviewer.md"

PASS_COUNT=0

assert_file_exists() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    printf 'FAIL: missing file %s\n' "$file" >&2
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

printf 'Running contract checks for /orchestrate ...\n'

assert_file_exists "$COMMAND_FILE"
assert_file_exists "$ORCHESTRATOR_AGENT"
assert_file_exists "$IMPL_AGENT"
assert_file_exists "$REVIEWER_AGENT"

# Command contract checks.
assert_contains "$COMMAND_FILE" 'Arguments: $ARGUMENTS'
assert_contains "$COMMAND_FILE" '- `--no-commit`: disable per-loop commits during this run.'
assert_contains "$COMMAND_FILE" '- `--commit`: force per-loop commits during this run.'
assert_contains "$COMMAND_FILE" '- If both flags are present, the last flag wins.'
assert_contains "$COMMAND_FILE" '- `exec <plan>` mode: if the first remaining token is `exec`, treat everything after `exec` as an approved plan and skip planning.'
assert_contains "$COMMAND_FILE" '- Resume mode: if there are no remaining arguments, attempt to resume from the latest approved plan in current conversation context.'
assert_contains "$COMMAND_FILE" 'Resume mode behavior (no args):'
assert_contains "$COMMAND_FILE" 'If an approved plan exists, call subagent `orchestrator-loop` immediately.'
assert_contains "$COMMAND_FILE" 'If no approved plan exists, ask the user to either:'
assert_contains "$COMMAND_FILE" '- Paste the full approved plan, or'
assert_contains "$COMMAND_FILE" '- Provide a goal so auto-planning can begin.'
assert_contains "$COMMAND_FILE" 'Ask the user to reply with exactly `APPROVE` to start implementation, or `EDIT: ...` to revise the plan.'
assert_contains "$COMMAND_FILE" 'Do not start implementation until explicit `APPROVE`.'
assert_contains "$COMMAND_FILE" 'call subagent `orchestrator-loop` with the approved plan'
assert_contains "$COMMAND_FILE" 'preserve phased structure for phase-by-phase execution'

# Orchestrator contract checks.
assert_contains "$ORCHESTRATOR_AGENT" 'Do not edit files directly.'
assert_contains "$ORCHESTRATOR_AGENT" 'Delegate code changes only to `impl-worker`.'
assert_contains "$ORCHESTRATOR_AGENT" 'Delegate evaluation only to `reviewer`.'
assert_contains "$ORCHESTRATOR_AGENT" 'Detect whether the approved plan is phased.'
assert_contains "$ORCHESTRATOR_AGENT" 'If phased, execute exactly ONE phase at a time.'
assert_contains "$ORCHESTRATOR_AGENT" 'Do not start the next phase until reviewer returns PASS for the current phase.'
assert_contains "$ORCHESTRATOR_AGENT" 'Keep impl-worker instructions scoped to the current phase only.'
assert_contains "$ORCHESTRATOR_AGENT" 'If commit mode is ON, create exactly one git commit per loop when repository changes exist.'
assert_contains "$ORCHESTRATOR_AGENT" 'If commit mode is OFF, do not create commits.'
assert_contains "$ORCHESTRATOR_AGENT" 'Never run `git push`, `git reset`, `git checkout`, or `git commit --amend`.'
assert_contains "$ORCHESTRATOR_AGENT" 'Commit message format: `orchestrate(loop N): <step summary>`.'
assert_contains "$ORCHESTRATOR_AGENT" '- Max loops: 3 (per phase cap)'
assert_contains "$ORCHESTRATOR_AGENT" 'Treat max loops as a per-phase cap.'
assert_contains "$ORCHESTRATOR_AGENT" 'If the current phase reaches cap without PASS, stop with PARTIAL and report remaining phases.'
assert_contains "$ORCHESTRATOR_AGENT" '    "*": allow'
assert_contains "$ORCHESTRATOR_AGENT" '- VERDICT: PASS or FAIL'
assert_contains "$ORCHESTRATOR_AGENT" '- OUTCOME: PASS or PARTIAL'
assert_contains "$ORCHESTRATOR_AGENT" '- PHASE_PROGRESS: current/total (or `non-phased`)'
assert_contains "$ORCHESTRATOR_AGENT" '- REMAINING_PHASES: bullet list (or `none`)'

# Worker/reviewer output schema checks.
assert_contains "$IMPL_AGENT" '- STATUS: DONE or BLOCKED'
assert_contains "$IMPL_AGENT" '- CHANGES: bullet list of file changes'
assert_contains "$IMPL_AGENT" '- COMMANDS_RUN: bullet list with command + short result'
assert_contains "$IMPL_AGENT" 'permission:'
assert_contains "$IMPL_AGENT" '    "*": allow'
assert_contains "$REVIEWER_AGENT" '- Do not edit files.'
assert_contains "$REVIEWER_AGENT" '    "*": allow'
assert_not_contains "$REVIEWER_AGENT" '    "*": ask'
assert_contains "$REVIEWER_AGENT" '- VERDICT: PASS or FAIL'
assert_contains "$REVIEWER_AGENT" '- MUST_FIX: bullet list (required when FAIL)'

printf 'PASS: %d contract checks\n' "$PASS_COUNT"
