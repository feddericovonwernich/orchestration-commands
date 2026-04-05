# Orchestration Command Installer

This package installs an OpenCode command that runs plan-first orchestration with implementation/review loops.

Installed artifacts:
- Command: `/<name>` (default `orchestrate`)
- Agents:
  - `orchestrator-loop` (subagent, hidden, creates one commit per loop when changes exist)
  - `impl-worker` (subagent)
  - `reviewer` (subagent, no file edits, test commands enabled)

## Install

```bash
chmod +x ./install.sh
./install.sh --scope project --path "$(pwd)"
```

## One-liner curl installers

- Project install (current directory):

```bash
curl -fsSL https://raw.githubusercontent.com/feddericovonwernich/orchestration-commands/main/install.sh | bash -s -- --scope project --path "$(pwd)"
```

- Global install:

```bash
curl -fsSL https://raw.githubusercontent.com/feddericovonwernich/orchestration-commands/main/install.sh | bash -s -- --scope global
```

- Project install with cleanup before linking:

```bash
curl -fsSL https://raw.githubusercontent.com/feddericovonwernich/orchestration-commands/main/install.sh | bash -s -- --scope project --path "$(pwd)" --clean
```

## Common options

```bash
./install.sh --scope project --path /path/to/repo
./install.sh --scope global
./install.sh --clone-dir ~/.local/share/opencode/sources/orchestration-commands
./install.sh --clean
./install.sh --dry-run
```

## Installer source of truth

- Installer source comes from a local git clone of this repository.
- Installed files are symlinks to `<clone-dir>/.opencode/...`.
- The installer prompts for clone location in interactive mode.
- Default clone location: `~/.local/share/opencode/sources/orchestration-commands`.
- You can override backup location used by `--clean`:

```bash
ORCHESTRATION_COMMANDS_BACKUP_DIR="/path/to/backups" ./install.sh --scope project --path "$(pwd)"
```

- To update after installation, run:

```bash
git -C <clone-dir> pull
```

## Command usage

- Auto mode (plan in main context first):

```txt
/orchestrate Add optimistic UI updates for comment posting
```

- Auto mode with commits disabled for this run:

```txt
/orchestrate --no-commit Add optimistic UI updates for comment posting
```

- Exec mode (skip planning, run loops immediately):

```txt
/orchestrate exec <approved plan text>
```

- Resume mode (no args: reuse latest approved plan from current conversation):

```txt
/orchestrate
```

If no approved plan is found in context, the command asks you to paste a full approved plan or provide a goal for auto-planning.

- Exec mode with commits disabled for this run:

```txt
/orchestrate --no-commit exec <approved plan text>
```

## Testing `/orchestrate`

- Run installer + contract checks (no model/provider needed):

```bash
bash tests/run.sh
```

- Run live smoke checks too (requires `opencode` CLI + provider auth):

```bash
OPENCODE_LIVE_TEST=1 bash tests/run.sh
```

- Optional: customize live test timeout (seconds):

```bash
OPENCODE_LIVE_TEST=1 OPENCODE_LIVE_TIMEOUT=180 bash tests/orchestrate-live.test.sh
```

## Notes

- Auto mode runs in `plan` agent with `subtask: false` so planning questions stay in the main context window.
- Implementation starts only after explicit `APPROVE` in auto mode.
- Approved phased plans are executed phase-by-phase; the next phase starts only after reviewer `PASS` on the current phase.
- Max loops is a per-phase cap. If a phase reaches cap without `PASS`, orchestration stops as `PARTIAL` and reports remaining phases.
- Commit mode is runtime-configurable: default ON, disable with `--no-commit`, re-enable with `--commit`.
- When commit mode is ON, orchestrator commits after each implementation loop when changes exist, with message format `orchestrate(loop N): <step summary>`.
- Orchestrator never pushes, amends, or runs destructive git commands.
- Use `--clean` to remove existing install files and backup directories before relinking.
