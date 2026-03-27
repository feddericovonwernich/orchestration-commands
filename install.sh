#!/usr/bin/env bash
set -euo pipefail

SCOPE="ask"
PROJECT_PATH=""
COMMAND_NAME="orchestrate"
MAX_LOOPS="3"
FORCE="0"
DRY_RUN="0"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

usage() {
  cat <<'EOF'
Usage:
  ./install.sh [options]

Options:
  --scope <project|global|ask>   Install scope (default: ask)
  --path <project-dir>           Project directory for project scope (default: current directory)
  --command-name <name>          Slash command name (default: orchestrate)
  --max-loops <n>                Maximum implementation/review loops (default: 3)
  --force                        Overwrite files without backups
  --dry-run                      Show actions without writing files
  -h, --help                     Show this help

Examples:
  ./install.sh --scope project
  ./install.sh --scope project --path /path/to/repo --command-name ship --max-loops 4
  ./install.sh --scope global --force
EOF
}

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

validate_positive_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

validate_command_name() {
  [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      [[ $# -ge 2 ]] || die "--scope requires a value"
      SCOPE="$2"
      shift 2
      ;;
    --path)
      [[ $# -ge 2 ]] || die "--path requires a value"
      PROJECT_PATH="$2"
      shift 2
      ;;
    --command-name)
      [[ $# -ge 2 ]] || die "--command-name requires a value"
      COMMAND_NAME="$2"
      shift 2
      ;;
    --max-loops)
      [[ $# -ge 2 ]] || die "--max-loops requires a value"
      MAX_LOOPS="$2"
      shift 2
      ;;
    --force)
      FORCE="1"
      shift
      ;;
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

case "$SCOPE" in
  project|global|ask)
    ;;
  *)
    die "Invalid --scope value '$SCOPE'. Expected project, global, or ask."
    ;;
esac

validate_command_name "$COMMAND_NAME" || die "Invalid command name '$COMMAND_NAME'. Use letters, numbers, dashes, or underscores."
validate_positive_int "$MAX_LOOPS" || die "Invalid --max-loops '$MAX_LOOPS'. Use a positive integer."

if [[ "$SCOPE" == "ask" ]]; then
  if [[ -t 0 ]]; then
    log "Choose install scope:"
    log "  1) project (.opencode in a repository)"
    log "  2) global (~/.config/opencode)"
    read -r -p "Enter choice [1/2]: " choice
    case "$choice" in
      1) SCOPE="project" ;;
      2) SCOPE="global" ;;
      *) die "Invalid choice '$choice'" ;;
    esac
  else
    SCOPE="project"
    log "Non-interactive mode detected; defaulting --scope to project"
  fi
fi

if [[ "$SCOPE" == "project" ]]; then
  if [[ -z "$PROJECT_PATH" ]]; then
    PROJECT_PATH="$PWD"
  fi
  [[ -d "$PROJECT_PATH" ]] || die "Project path does not exist: $PROJECT_PATH"
  BASE_DIR="$PROJECT_PATH/.opencode"
else
  BASE_DIR="$HOME/.config/opencode"
fi

AGENTS_DIR="$BASE_DIR/agents"
COMMANDS_DIR="$BASE_DIR/commands"
COMMAND_FILE="$COMMANDS_DIR/${COMMAND_NAME}.md"

emit_orchestrator_agent() {
  cat <<'EOF'
---
description: Orchestrates implementation and review loops until pass or loop cap.
mode: subagent
hidden: true
temperature: 0.1
tools:
  read: true
  glob: true
  grep: true
  task: true
  bash: true
  write: false
  edit: false
  patch: false
permission:
  task:
    "*": deny
    "impl-worker": allow
    "reviewer": allow
  bash:
    "*": deny
    "git rev-parse*": allow
    "git status*": allow
    "git diff*": allow
    "git add*": allow
    "git commit*": allow
    "git log*": allow
---

You are the orchestration controller.

Inputs include:
- Goal and context
- Approved implementation plan
- Max loops: __MAX_LOOPS__
- Commit mode: ON (default) or OFF

Rules:
- Do not edit files directly.
- Delegate code changes only to `impl-worker`.
- Delegate evaluation only to `reviewer`.
- Keep each loop focused on the smallest set of required fixes.
- If commit mode is ON, create exactly one git commit per loop when repository changes exist.
- If commit mode is OFF, do not create commits.
- Never run `git push`, `git reset`, `git checkout`, or `git commit --amend`.
- Never commit likely secret files, including `.env`, `.env.*`, `*.pem`, `*.key`, or `*credentials*.json`.
- Commit message format: `orchestrate(loop N): <step summary>`.

Loop process:
1. Send clear implementation instructions to `impl-worker` for the next plan step or required fixes.
2. If commit mode is ON, check whether the workspace is a git repository.
3. If commit mode is ON and this is a git repository, check repository state with git commands.
4. If commit mode is ON and there are changes, stage only relevant non-secret files and create one commit for this loop.
5. If commit mode is OFF, record `NO_COMMIT(loop N, disabled)` for this loop.
6. If commit mode is ON and no changes exist or this is not a git repository, record `NO_COMMIT` for this loop and continue.
7. Send reviewer instructions to `reviewer` with acceptance criteria and expected output format.
8. If reviewer verdict is PASS, stop.
9. If reviewer verdict is FAIL, extract only MUST_FIX items and run another loop.
10. Stop when loops reach __MAX_LOOPS__.

Commit safety and behavior:
- If commit mode is ON and commit fails due to hooks or validation, send the failure details to `impl-worker`, request a targeted fix, then retry commit once for the same loop.
- Keep commits scoped to the loop's requested work only.
- Capture commit hash and subject line for final reporting.

When asking `reviewer`, require this format:
- VERDICT: PASS or FAIL
- MUST_FIX: bullet list
- NICE_TO_HAVE: bullet list
- EVIDENCE: bullet list of checks and findings

Final response format:
- OUTCOME: PASS or PARTIAL
- LOOPS_USED: n/__MAX_LOOPS__
- COMMITS: bullet list of `<hash> <subject>` or `NO_COMMIT(loop N, reason)`
- CHANGED_FILES: bullet list
- VALIDATION: bullet list of checks run and results
- REMAINING_RISKS: bullet list (or "none")
- NEXT_ACTIONS: bullet list
EOF
}

emit_impl_worker_agent() {
  cat <<'EOF'
---
description: Implements approved plan steps and targeted fixes.
mode: subagent
temperature: 0.2
tools:
  read: true
  glob: true
  grep: true
  write: true
  edit: true
  patch: true
  bash: true
---

You are the implementation worker.

Rules:
- Implement only what the orchestrator requests.
- Keep changes focused and minimal.
- Preserve existing style and conventions.
- Run only relevant checks for the requested scope.
- If blocked, stop and explain exactly what is missing.

Response format:
- STATUS: DONE or BLOCKED
- CHANGES: bullet list of file changes
- COMMANDS_RUN: bullet list with command + short result
- NOTES: concise blockers, tradeoffs, or follow-ups
EOF
}

emit_reviewer_agent() {
  cat <<'EOF'
---
description: Reviews implementation output and runs verification commands without editing files.
mode: subagent
temperature: 0.1
tools:
  read: true
  glob: true
  grep: true
  bash: true
  write: false
  edit: false
  patch: false
permission:
  bash:
    "*": ask
    "npm test*": allow
    "npm run test*": allow
    "npm run lint*": allow
    "npm run build*": allow
    "pnpm test*": allow
    "pnpm run test*": allow
    "pnpm run lint*": allow
    "pnpm run build*": allow
    "yarn test*": allow
    "yarn run test*": allow
    "yarn run lint*": allow
    "yarn run build*": allow
    "bun test*": allow
    "bun run test*": allow
    "bun run lint*": allow
    "bun run build*": allow
    "pytest*": allow
    "go test*": allow
    "cargo test*": allow
    "git status*": allow
    "git diff*": allow
    "git log*": allow
---

You are the reviewer.

Rules:
- Do not edit files.
- Validate the implementation against the requested plan step and acceptance criteria.
- Run useful verification commands when available.
- Be strict about correctness, regressions, and missing requirements.

Response format:
- VERDICT: PASS or FAIL
- MUST_FIX: bullet list (required when FAIL)
- NICE_TO_HAVE: bullet list
- EVIDENCE: bullet list of checks and findings
EOF
}

emit_command_file() {
  cat <<'EOF'
---
description: Plan-first orchestration with implementation/review loops.
agent: plan
subtask: false
---

You are running the orchestration command.

Arguments: $ARGUMENTS

Runtime flags:
- `--no-commit`: disable per-loop commits during this run.
- `--commit`: force per-loop commits during this run.
- If both flags are present, the last one wins.
- If neither flag is provided, default to commit mode ON.

Argument parsing:
- Parse and remove runtime flags first.
- Then detect mode:
  - If the first remaining token is `exec`, treat everything after `exec` as an approved plan and skip planning.
  - Otherwise run auto-planning in the main context first.

Exec mode behavior:
1. If `exec` has no plan content, ask the user for a full approved plan.
2. If plan content is present, call subagent `orchestrator-loop` immediately.
3. Pass goal/context, approved plan text, max loops __MAX_LOOPS__, and commit mode ON/OFF to the subagent.

Auto mode behavior (default):
1. Treat the remaining non-flag arguments as the goal.
2. Ask concise clarifying questions only when needed.
3. Produce a concrete plan with:
   - Scope and assumptions
   - Step-by-step implementation tasks
   - Acceptance criteria
   - Validation commands
   - Risks and rollback notes
4. Ask the user to reply with exactly `APPROVE` to start implementation, or `EDIT: ...` to revise the plan.
5. Do not start implementation until explicit `APPROVE`.
6. On `EDIT: ...`, revise the plan and ask for `APPROVE` again.
7. On `APPROVE`, call subagent `orchestrator-loop` with the approved plan, max loops __MAX_LOOPS__, and commit mode ON/OFF.

Execution notes:
- Keep planning interaction in this main context window.
- Keep outputs concise and structured.
- Commit mode defaults to ON unless `--no-commit` is provided.
- After orchestration finishes, provide final outcome, commits, changed files, validation results, and remaining risks.
EOF
}

install_from_template() {
  local target="$1"
  local template_fn="$2"
  local tmp_template
  local tmp_rendered

  tmp_template="$(mktemp)"
  tmp_rendered="$(mktemp)"

  "$template_fn" >"$tmp_template"
  sed -e "s/__MAX_LOOPS__/${MAX_LOOPS}/g" "$tmp_template" >"$tmp_rendered"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] Would write: $target"
    if [[ -e "$target" && "$FORCE" == "0" ]]; then
      log "[dry-run] Would backup existing file: ${target}.bak.${TIMESTAMP}"
    fi
  else
    mkdir -p "$(dirname "$target")"
    if [[ -e "$target" && "$FORCE" == "0" ]]; then
      local backup
      backup="${target}.bak.${TIMESTAMP}"
      cp "$target" "$backup"
      log "Backed up: $target -> $backup"
    fi
    cp "$tmp_rendered" "$target"
    log "Installed: $target"
  fi

  rm -f "$tmp_template" "$tmp_rendered"
}

if [[ "$DRY_RUN" == "1" ]]; then
  log "[dry-run] Target base: $BASE_DIR"
  log "[dry-run] Scope: $SCOPE"
  log "[dry-run] Command name: /$COMMAND_NAME"
  log "[dry-run] Max loops: $MAX_LOOPS"
else
  mkdir -p "$AGENTS_DIR" "$COMMANDS_DIR"
fi

install_from_template "$AGENTS_DIR/orchestrator-loop.md" emit_orchestrator_agent
install_from_template "$AGENTS_DIR/impl-worker.md" emit_impl_worker_agent
install_from_template "$AGENTS_DIR/reviewer.md" emit_reviewer_agent
install_from_template "$COMMAND_FILE" emit_command_file

if [[ "$DRY_RUN" == "1" ]]; then
  log ""
  log "Dry run complete. No files were written."
else
  log ""
  log "Install complete."
fi

log ""
log "Installed command: /$COMMAND_NAME"
log "Try:"
log "  /$COMMAND_NAME Build a feature to ..."
log "  /$COMMAND_NAME exec <approved plan text>"
