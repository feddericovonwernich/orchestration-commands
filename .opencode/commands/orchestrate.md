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
- If both flags are present, the last flag wins.
- If neither flag is provided, default to commit mode ON.

Argument parsing:
- Parse and remove runtime flags first.
- Then detect mode:
  - `exec <plan>` mode: if the first remaining token is `exec`, treat everything after `exec` as an approved plan and skip planning.
  - Resume mode: if there are no remaining arguments, attempt to resume from the latest approved plan in current conversation context.
  - Auto mode: otherwise run auto-planning in the main context first.

Exec mode behavior:
1. If `exec` has no plan content, ask the user for a full approved plan.
2. If plan content is present, call subagent `orchestrator-loop` immediately.
3. Pass goal/context, approved plan text, max loops 3 (per phase), commit mode ON/OFF, and preserve phased structure for phase-by-phase execution.

Resume mode behavior (no args):
1. Attempt to find the latest approved plan in the current conversation context.
2. If an approved plan exists, call subagent `orchestrator-loop` immediately.
3. Pass goal/context, approved plan text, max loops 3 (per phase), commit mode ON/OFF, and preserve phased structure for phase-by-phase execution.
4. If no approved plan exists, ask the user to either:
   - Paste the full approved plan, or
   - Provide a goal so auto-planning can begin.

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
7. On `APPROVE`, call subagent `orchestrator-loop` with the approved plan, max loops 3 (per phase), commit mode ON/OFF, and preserve phased structure for phase-by-phase execution.

Execution notes:
- Keep planning interaction in this main context window.
- Keep outputs concise and structured.
- Commit mode defaults to ON unless `--no-commit` is provided.
- After orchestration finishes, provide final outcome, commits, changed files, validation results, and remaining risks.
