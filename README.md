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
./install.sh
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

- Project install with custom command name and loop cap:

```bash
curl -fsSL https://raw.githubusercontent.com/feddericovonwernich/orchestration-commands/main/install.sh | bash -s -- --scope project --path "$(pwd)" --command-name ship --max-loops 4
```

## Common options

```bash
./install.sh --scope project --path /path/to/repo
./install.sh --scope global
./install.sh --command-name ship --max-loops 4
./install.sh --dry-run
```

## Installer source of truth

- Installer content comes from repository files under `.opencode/`.
- Re-running `install.sh` updates existing installed files to match the current source (with backups unless `--force`).
- If local `.opencode/` sources are unavailable (for example one-line curl install), installer falls back to remote raw files.
- You can pin remote fallback source with:

```bash
ORCHESTRATION_COMMANDS_SOURCE_REF=<branch-or-tag> ./install.sh --scope project --path "$(pwd)"
```

- Or override the fallback base URL directly:

```bash
ORCHESTRATION_COMMANDS_SOURCE_BASE_URL="https://raw.githubusercontent.com/<owner>/<repo>/<ref>/.opencode" ./install.sh --scope project --path "$(pwd)"
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

- Exec mode with commits disabled for this run:

```txt
/orchestrate exec --no-commit <approved plan text>
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
- Commit mode is runtime-configurable: default ON, disable with `--no-commit`, re-enable with `--commit`.
- When commit mode is ON, orchestrator commits after each implementation loop when changes exist, with message format `orchestrate(loop N): <step summary>`.
- Orchestrator never pushes, amends, or runs destructive git commands.
- Existing command/agent files are backed up with a timestamp unless `--force` is used.
