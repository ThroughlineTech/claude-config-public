---
mode: agent
description: Rebase, test, merge, archive, and optionally deploy a ticket
argument-hint: 'TKT-XXX'
---

# Ship a Ticket

You are merging an approved ticket to main and (optionally) deploying.

## Input

Argument: a ticket ID (e.g., `TKT-001`).

**ID shorthand:** If the argument is a bare number (e.g., `26` or `3`), resolve it to a full ticket ID: read the ticket prefix from `.claude/ticket-config.md`, scan existing ticket files to determine zero-padding width, and expand (e.g., `26` → `TKT-026`).

**Locate the ticket file:** it must be at `{tickets-dir}/{ID}.md` (active set). If it lives in `shipped/`, `deferred/`, or `wontfix/`, STOP — a terminal ticket cannot be shipped again. (Use `/ticket-reopen {ID}` if this is an intentional re-ship.)

## Pre-flight Checks

- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- Read Test, Build, and Deploy commands from `.claude/ticket-config.md`.
- Ticket status MUST be `review` (meaning human has verified). If not, report status and stop.
- Ensure we're on the ticket's feature branch.
- Ensure working tree is clean.
- Determine the main branch: read `Main branch` from `.claude/ticket-config.md` if present. Otherwise fall back to `git symbolic-ref refs/remotes/origin/HEAD`. If the result is `master`, warn and suggest `/ticket-install`.

## Phase 1: Final Regression Test

1. Pull latest main: `git fetch origin {main}`
2. Rebase onto main: `git rebase origin/{main}`
   - If conflicts arise, STOP and report them. Do NOT auto-resolve.
3. Run Test command. ALL tests must pass after rebase. If any fail, STOP and report.
4. Run Build command. Must be clean. If errors, STOP and report.

## Phase 2: Write Regression Report

Update the ticket's Regression Report section:
```markdown
## Regression Report
- Rebase onto {main}: clean (no conflicts)
- Tests after rebase: X passing, 0 failing (or: skipped — no test command configured)
- Build after rebase: clean (or: skipped)
- Tested at: {timestamp}
```

## Phase 3: Merge

1. Switch to main: `git checkout {main}`
2. Pull latest: `git pull origin {main}`
3. Merge: `git merge ticket/{branch-name} --no-ff -m "Merge {TKT-ID}: {title}"`
4. Run Test command one final time on main. If ANY test fails: `git reset --hard HEAD~1` and report. Do NOT push broken code.
5. Run Build command one final time. Same: reset and report on failure.

## Phase 4: Deploy (skip if no Deploy command configured)

If `.claude/ticket-config.md` has a Deploy command:
1. Push to remote: `git push origin {main}`
2. Run the Deploy command.
3. Wait for deploy to complete and note status.

If Deploy is empty or `(none)`:
1. Push to remote: `git push origin {main}`
2. Skip deploy; note in output that no deploy is configured.

## Phase 5: Cleanup

1. Delete the feature branch: `git branch -d ticket/{branch-name}`
2. Update ticket status to `shipped`.
3. Update the `updated` date.

## Phase 6: Archive the Ticket File

Move the ticket (and any sibling brief files) into `{tickets-dir}/shipped/`:

1. Create `{tickets-dir}/shipped/` if it does not exist.
2. Move with `git mv` (NOT `cp`, NOT plain `mv`):
   ```
   git mv {tickets-dir}/{TKT-ID}.md {tickets-dir}/shipped/{TKT-ID}.md
   ```
3. Move any sibling brief files:
   ```
   git mv {tickets-dir}/{TKT-ID}.*.brief.md {tickets-dir}/shipped/
   ```
   Skip if none exist.
4. Commit: `git commit -m "{TKT-ID}: archive shipped ticket"`
5. Push: `git push origin {main}`

## Phase 7: Decruft (automatic worktree + preview teardown)

1. **Kill preview components for this ticket** (if any):
   - Read `.worktrees/ticket-{lowercased-id}/.preview.pid` if present. Each line is `{component-name}  {pid}  {port}`.
   - Kill each PID in **reverse launch order** (SIGTERM first, SIGKILL after 3s). On Windows: `taskkill /F /PID {pid}`. Skip rows with PID `-`.
   - Delete `.preview.pid` and `.preview.meta` files.
2. **Remove the ticket's worktree:**
   - `git worktree remove .worktrees/ticket-{lowercased-id}` (with `--force` as fallback).
   - If that fails: `rm -rf .worktrees/ticket-{lowercased-id}` + `git worktree prune`.
3. **If a rollup preview is currently live** (a worktree at `.worktrees/batch-preview-*/` with a live `.preview.pid`), rebuild it excluding this ticket. If no `review`-status tickets remain, kill the rollup and don't rebuild.
4. Report any decruft actions in the final output.

## Finish

Output:
```
{ID} SHIPPED

Merged to {main}: {merge commit hash}
Deployed: {timestamp or "skipped — no deploy configured"}
Branch cleaned up: yes

Summary: {1-2 sentence description of what shipped}

The ticket has the full history.
```

## Rules

- NEVER force push to main.
- NEVER push if tests or build fail after merge.
- If anything goes wrong during merge/deploy, reset to a safe state and report.
- The merge commit message must reference the ticket ID.
- Ask for confirmation before pushing to main if this is the first time using this workflow in the project.

## Compatibility Notes

- All source behaviors preserved exactly. No Copilot-specific adaptations required.
