---
mode: agent
description: Close a ticket as wontfix
argument-hint: 'TKT-XXX {reason...}'
---

# Close a Ticket (wontfix)

Move an active ticket to the `wontfix/` subfolder. "Close" means "done thinking about this — it won't be done": duplicate, invalid, obsolete, rejected, superseded. Unlike `/ticket-defer`, closed tickets are not expected to come back (though `/ticket-reopen` is always available).

## Input

Arguments: `{ID} {reason...}`

**ID shorthand:** If the ID is a bare number (e.g., `26` or `3`), resolve it to a full ticket ID: read the ticket prefix from `.claude/ticket-config.md`, scan existing ticket files to determine zero-padding width, and expand (e.g., `26` → `TKT-026`).

The reason is **REQUIRED**. Everything after the ID is treated as the reason text. The reason may be given in any language; translate to clear, concise English before writing.

Examples:
- `TKT-007 duplicate of TKT-012`
- `TKT-031 obsolete — the whole subsystem was deleted in TKT-029`
- `TKT-042 ugyldig — bug eksisterer ikke længere` → translate → "invalid — bug no longer exists"

If no reason is supplied, STOP and tell the user: "`/ticket-close` requires a reason. Usage: `/ticket-close {ID} {reason}`"

## Pre-flight Checks

- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- Locate the ticket file at `{tickets-dir}/{ID}.md`. If it's already in a terminal subfolder, STOP and report where it is.
- If the ticket has a non-empty `branch` field with unmerged work, warn: "This ticket has branch `{branch}` with possibly-unmerged commits — close anyway?" Only proceed on explicit confirmation. Do NOT delete the branch automatically.

## Steps

1. **Translate the reason to English** if it isn't already.

2. **Update the ticket file in place:**
   - Set `status: wontfix`
   - Update the `updated` date to today
   - Append:
     ```markdown
     ## Closed (wontfix)
     - Closed at: {YYYY-MM-DD}
     - Reason: {translated reason in English}
     ```

3. **Lazily create** `{tickets-dir}/wontfix/` if it does not exist.

4. **Move with `git mv`** (NOT `cp`, NOT plain `mv`):
   ```
   git mv {tickets-dir}/{ID}.md {tickets-dir}/wontfix/{ID}.md
   ```

5. **Move sibling brief files** the same way if any exist:
   ```
   git mv {tickets-dir}/{ID}.*.brief.md {tickets-dir}/wontfix/
   ```

6. **Commit:**
   ```
   git add {tickets-dir}/wontfix/{ID}.md
   git commit -m "{ID}: close (wontfix) — {short reason}"
   ```

7. **Decruft (automatic):**
   - Read `.worktrees/ticket-{lowercased-id}/.preview.pid` if present. Kill each PID in reverse launch order (SIGTERM, then SIGKILL after 3s; Windows: `taskkill /F /PID {pid}`). Delete PID/meta files.
   - `git worktree remove .worktrees/ticket-{lowercased-id}` (with `--force` fallback).
   - If a rollup preview is live, rebuild it excluding this ticket (or kill it if no `review` tickets remain).
   - Report cleanup actions in the final output.

## Finish

Output:
```
{ID} CLOSED (wontfix)

Moved to: {tickets-dir}/wontfix/{ID}.md
Reason: {translated reason}

If this turns out to be wrong, /ticket-reopen {ID} brings it back.
```

## Rules

- Reason stored in English only — translate once, do not keep the original language.
- Do not delete brief files; they remain part of the audit trail.

## Compatibility Notes

- All source behaviors preserved exactly. No Copilot-specific adaptations required.
