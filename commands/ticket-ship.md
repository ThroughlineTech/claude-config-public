# Ship a Ticket

You are merging an approved ticket to main and (optionally) deploying.

## Input
The argument is a ticket ID (e.g., TKT-001). Read the ticket file from the project's tickets directory (see `.claude/ticket-config.md`).

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
