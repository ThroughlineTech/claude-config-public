---
mode: agent
description: Reap stale worktrees and preview processes
argument-hint: '[TKT-XXX | --all]'
---

# Reap Stale Worktrees and Previews

Removes worktrees and kills preview processes for tickets that no longer need them — because they shipped, were closed, deferred, or the ticket file was deleted entirely. Also used to explicitly tear down a single ticket's preview.

## Input

One of:
- `{ID}` — tear down the worktree and preview for this specific ticket (regardless of its current status)
- `--all` — reap every worktree + preview in the project (nuclear option — stops everything)
- *(no args)* — reap **stale** worktrees only: tickets in a terminal folder or not found. Active tickets are left alone.

**ID shorthand:** If the ID is a bare number (e.g., `14` or `3`), resolve it to a full ticket ID: read the ticket prefix from `.claude/ticket-config.md`, scan existing ticket files to determine zero-padding width, and expand (e.g., `14` → `TKT-014`).

## Pre-flight

Must be run from a project root. No config required — cleanup must work even if `.claude/ticket-config.md` is missing.

## Steps

### 1. Enumerate existing worktrees

- List directories matching `.worktrees/ticket-*/` and `.worktrees/batch-preview-*/`.
- Also run `git worktree list --porcelain` to catch registered worktrees not found by directory scan.

### 2. For each worktree, decide the action

For `ticket-*` worktrees:
- Extract the ticket ID from the directory name (`ticket-tkt-014` → `TKT-014`).
- Determine where the ticket file lives:
  - Active: `{tickets-dir}/{ID}.md` → **keep** (unless this is the targeted `{ID}` or `--all`)
  - Terminal (`shipped/`, `deferred/`, `wontfix/`) → **reap**
  - Not found anywhere → **reap** (orphaned)

For `batch-preview-*` worktrees:
- Reap any that are older than 24 hours OR if `--all` was passed OR if no `.preview.pid` exists.

### 3. Reap action (for each worktree being cleaned up)

1. **Kill all preview components** if any are running:
   - Read `.worktrees/{name}/.preview.pid` if it exists. Each line: `{component-name}  {pid}  {port}`.
   - Iterate in **reverse** order (last launched is first killed). Skip rows with PID `-`.
   - Kill with SIGTERM first; if still alive after 3 seconds, SIGKILL. On Windows: `taskkill /F /PID {pid}`.
   - If a kill fails, log it and continue — don't let one zombie block the rest.
   - After all rows: delete `.preview.pid` and `.preview.meta` files.

2. **Remove the git worktree:**
   - `git worktree remove .worktrees/{name}` (clean path).
   - If that fails and this is a terminal ticket or `--all`: `git worktree remove --force .worktrees/{name}`.
   - If that also fails: `rm -rf .worktrees/{name}` + `git worktree prune`.

3. **Delete the feature branch** if it's fully merged into main and the ticket is in `shipped/`:
   - `git branch -d ticket/{...}` — safe delete (only works if merged).
   - Never use `-D` (force delete); if unmerged, leave it and report.

### 4. Report

```
CLEANUP COMPLETE

Reaped worktrees:
  .worktrees/ticket-tkt-014  (TKT-014, shipped)      preview PID 12345 killed, port 3014 freed
  .worktrees/ticket-tkt-015  (TKT-015, deferred)     preview not running
  .worktrees/batch-preview-2026-04-08-1423            preview PID 12890 killed, port 3999 freed

Branches deleted:
  ticket/tkt-014-fix-auth-redirect   (merged, safe delete)

Kept:
  .worktrees/ticket-tkt-016  (TKT-016, status: review — still active)
  .worktrees/ticket-tkt-017  (TKT-017, status: in-progress — still active)

Warnings:
  ticket/tkt-018-foo not deleted — has unmerged commits. Review manually.
```

If nothing was reaped:
```
CLEANUP: nothing to reap. 3 active worktrees left alone.
```

## Rules

- **Active tickets are never touched by the no-arg form.** Pass `{ID}` explicitly or `--all` to tear down an in-flight ticket.
- **Force-remove only for terminal tickets.** An active ticket with a dirty worktree means work is in progress — never blow it away by default.
- **Never `-D` branches in cleanup.** If a branch has unmerged commits, report it and leave it.
- **Preview process kill is best-effort.** If the PID no longer exists or the kill fails harmlessly, log it and continue.
- **This command is idempotent.** Running it twice should be safe and produce "nothing to reap" the second time.
- **When called inline from another command's preflight** (auto-reap in `/ticket-list`, `/ticket-status`, `/ticket-batch`), run in silent mode — only report if something was actually reaped, as a single one-line note.

## Compatibility Notes

- All source behaviors preserved exactly. No Copilot-specific adaptations required.
