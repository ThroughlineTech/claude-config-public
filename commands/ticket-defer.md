# Defer a Ticket

Move an active ticket to the `deferred/` subfolder. Deferred means "investigated or considered, not now, may revisit later." The ticket is preserved with a reason so future-you knows why it was parked.

## Input

Arguments: `{ID} {reason...}`

The reason is REQUIRED. Everything after the ID is treated as the reason text. The reason may be given in **any language** (e.g. Danish). Before writing it into the ticket, **translate it to clear, concise English**.

Examples:
- `/ticket-defer TKT-014 too big a refactor for this sprint, revisit after the auth rewrite lands`
- `/ticket-defer TKT-022 for stort et refaktor lige nu` → translate → "too large a refactor right now"

If no reason is supplied, STOP and tell the user: "`/ticket-defer` requires a reason. Usage: `/ticket-defer {ID} {reason}`".

## Pre-flight Checks

- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- **Locate the ticket file** at `{tickets-dir}/{ID}.md`. If it's already in a terminal subfolder (`shipped/`, `deferred/`, `wontfix/`), STOP and report where it is.
- Working tree should be clean (or only contain the ticket file being moved). If dirty in an unrelated way, warn and ask before proceeding.

## Steps

1. **Translate the reason to English** if it isn't already. Keep it short — one or two sentences.

2. **Update the ticket file in place** (before moving it):
   - Set `status: deferred`
   - Update the `updated` date to today
   - Append a new section at the bottom:
     ```markdown
     ## Deferred
     - Deferred at: {YYYY-MM-DD}
     - Reason: {translated reason in English}
     ```
   - If a `## Deferred` section already exists (rare — from a prior defer/reopen cycle), append a new dated entry rather than overwriting.

3. **Lazily create** `{tickets-dir}/deferred/` if it does not exist. Do NOT add a `.gitkeep`; the `git mv` below will populate it.

4. **Move the ticket with `git mv`** (NOT `cp`, NOT plain `mv`):
   ```
   git mv {tickets-dir}/{ID}.md {tickets-dir}/deferred/{ID}.md
   ```

5. **Move any sibling brief files** the same way, if any exist:
   ```
   git mv {tickets-dir}/{ID}.*.brief.md {tickets-dir}/deferred/
   ```
   Skip silently if none exist.

6. **Commit** the status edit and move together:
   ```
   git add {tickets-dir}/deferred/{ID}.md
   git commit -m "{ID}: defer — {short reason}"
   ```

7. **Decruft (automatic)** — same contract as `/ticket-ship` Phase 7:
   - Read `.worktrees/ticket-{lowercased-id}/.preview.pid` (multi-line: one `{component} {pid} {port}` row per component). Kill each live PID in reverse launch order. Delete PID/meta files.
   - `git worktree remove .worktrees/ticket-{lowercased-id}` (with `--force` fallback).
   - If a rollup preview is currently live, rebuild it **excluding** this ticket (kill current rollup's components, recreate scratch branch from main merging the remaining `review`-status ticket branches, relaunch the compound/atomic profile for the rollup). If no `review` tickets remain in the batch, just kill the rollup.
   - Report cleanup actions in the final output.

## Finish

Output:
```
{ID} DEFERRED

Moved to: {tickets-dir}/deferred/{ID}.md
Reason: {translated reason}

To bring it back: /ticket-reopen {ID}
```

## Rules

- Never defer a ticket that's already on a feature branch with unmerged work without warning the user first. If the ticket has a non-empty `branch` field, ask: "This ticket has branch `{branch}` — defer anyway? The branch will be left as-is." Only proceed on explicit confirmation.
- Do not delete brief files; they're part of the audit trail.
- If the reason was given in a non-English language, the English translation is what gets written to the ticket. Do not store both.
