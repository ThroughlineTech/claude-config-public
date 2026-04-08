# Ship a Ticket

You are merging an approved ticket to main and (optionally) deploying.

## Input
The argument is a ticket ID (e.g., TKT-001).

**Locate the ticket file:** it must be at `{tickets-dir}/{ID}.md` (active set). If it lives in `shipped/`, `deferred/`, or `wontfix/`, STOP — a terminal ticket cannot be shipped again. (Use `/ticket-reopen {ID}` if this is an intentional re-ship.)

## Pre-flight Checks
- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- Read Test, Build, and Deploy commands from `.claude/ticket-config.md`.
- Ticket status MUST be `review` (meaning human has verified). If not, report status and stop.
- Ensure we're on the ticket's feature branch.
- Ensure working tree is clean.
- Determine the main branch name (`main`, `master`, or `develop`).

## Phase 1: Final Regression Test

1. **Pull latest main**: `git fetch origin {main}`
2. **Rebase onto main**: `git rebase origin/{main}`
   - If conflicts arise, STOP and report them. Do NOT auto-resolve.
3. **Run Test command** from config. ALL tests must pass after rebase. If any fail, STOP and report. (Skip if no Test command configured.)
4. **Run Build command** from config. Must be clean. If errors, STOP and report. (Skip if no Build command configured.)

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
3. Merge the feature branch: `git merge ticket/{branch-name} --no-ff -m "Merge {TKT-ID}: {title}"`
4. Run Test command one final time on main. If ANY test fails after merge, IMMEDIATELY: `git reset --hard HEAD~1` and report. Do NOT push broken code.
5. Run Build command one final time. Same: if it fails, reset and report.

## Phase 4: Deploy (skip if no Deploy command configured)

If `.claude/ticket-config.md` has a Deploy command:
1. **Push to remote**: `git push origin {main}`
2. **Deploy**: run the Deploy command from config
3. Wait for deploy to complete and note status.

If Deploy is empty or `(none)`:
1. **Push to remote**: `git push origin {main}`
2. Skip the deploy step entirely; note in the output that no deploy is configured.

## Phase 5: Cleanup

1. Delete the feature branch: `git branch -d ticket/{branch-name}`
2. Update ticket status to `shipped`
3. Update the `updated` date

## Phase 6: Archive the ticket file

Move the ticket (and any sibling brief files) into `{tickets-dir}/shipped/` so the active set stays clean.

1. Create `{tickets-dir}/shipped/` if it does not yet exist (lazy creation — no `.gitkeep`, the first `git mv` populates it).
2. Move the ticket file with `git mv` (NOT `cp`, NOT plain `mv` — we want git to track the rename so history is preserved):
   ```
   git mv {tickets-dir}/{TKT-ID}.md {tickets-dir}/shipped/{TKT-ID}.md
   ```
3. Move any associated brief files the same way:
   ```
   git mv {tickets-dir}/{TKT-ID}.*.brief.md {tickets-dir}/shipped/
   ```
   (Skip this if no brief files exist for the ticket.)
4. Commit the move on `{main}`: `git commit -m "{TKT-ID}: archive shipped ticket"`
5. Push: `git push origin {main}`

## Phase 7: Decruft (automatic worktree + preview teardown)

This phase runs automatically — the user never asks for it. It is the mechanism that keeps the project tree clean.

1. **Kill all preview components for this ticket** (one ticket can run multiple components if it used a compound profile):
   - Read `.worktrees/ticket-{lowercased-id}/.preview.pid` if present. Each line is `{component-name}  {pid}  {port}`.
   - Kill each PID in **reverse launch order** (last-launched first — so dependents go down before the things they depend on). Skip lines where PID is `-` (command-exit components, nothing persistent to kill).
   - Use SIGTERM first, escalate to SIGKILL after 3 seconds per PID. On Windows, `taskkill /F /PID {pid}`.
   - Delete the `.preview.pid` and `.preview.meta` files.
2. **Remove the ticket's worktree** if one exists:
   - `git worktree remove .worktrees/ticket-{lowercased-id}` (with `--force` as a fallback — by ship time the worktree's contents don't matter).
   - If that fails entirely, `rm -rf .worktrees/ticket-{lowercased-id}` + `git worktree prune`.
3. **If a rollup preview is currently live** (a worktree at `.worktrees/batch-preview-*/` with a live `.preview.pid`), rebuild it:
   - Kill the current rollup preview.
   - Remove the current rollup scratch branch.
   - Recreate the rollup from `{main}` by merging every remaining `review`-status ticket branch in the batch in ID order.
   - Relaunch the preview on the new rollup.
   - If no `review`-status tickets remain, just kill the rollup and don't rebuild.
4. Report any decruft actions in the final output so the user knows what was cleaned up.

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
