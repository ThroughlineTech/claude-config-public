# Reopen a Ticket

Bring a ticket out of a terminal subfolder (`shipped/`, `deferred/`, `wontfix/`) back into the active set. Use this when a shipped change regressed, a deferred ticket's moment has come, or a closed ticket turned out to be real after all.

## Input

Arguments: `{ID} [reason...]`

The reason is optional but **strongly recommended** — especially when reopening from `shipped/` (which almost always means a regression). The reason may be given in **any language**; translate to English before writing.

Examples:
- `/ticket-reopen TKT-014 customer hit the original bug again after the merge, logs attached`
- `/ticket-reopen TKT-022`  (permitted, but the ticket will get a generic "reopened" note)

## Pre-flight Checks

- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- **Locate the ticket file** — search `{tickets-dir}/shipped/{ID}.md`, `{tickets-dir}/deferred/{ID}.md`, `{tickets-dir}/wontfix/{ID}.md`. If it is already at `{tickets-dir}/{ID}.md` (active), STOP and report "ticket is already active".
- If not found anywhere, error out.

## Steps

1. **Determine the new active status** based on where the ticket came from and what's filled in:
   - From `shipped/` → `open` (regression; investigation should start over, because the prior investigation is stale by definition)
   - From `deferred/` → best-guess from the ticket's content:
     - If `Implementation Plan` is filled and `branch` is still set → `proposed`
     - Otherwise → `open`
   - From `wontfix/` → `open` (start fresh)
   - **When in doubt, use `open`.** It's always safe.

2. **Translate the reason to English** if one was given. If none was given, use a default: "reopened on {date}".

3. **Update the ticket file in place**:
   - Set `status` to the new active status chosen above
   - Update the `updated` date to today
   - Append:
     ```markdown
     ## Reopened
     - Reopened at: {YYYY-MM-DD}
     - Previous state: {shipped|deferred|wontfix}
     - Reason: {translated reason or default}
     ```
   - **Do NOT delete** the existing `## Shipped`, `## Deferred`, or `## Closed (wontfix)` sections. Keep them — they're history. A ticket may acquire multiple `## Reopened` / `## Deferred` blocks over its life.

4. **Move the ticket back to the active root with `git mv`**:
   ```
   git mv {tickets-dir}/{previous-folder}/{ID}.md {tickets-dir}/{ID}.md
   ```

5. **Move any sibling brief files** back too:
   ```
   git mv {tickets-dir}/{previous-folder}/{ID}.*.brief.md {tickets-dir}/
   ```
   Skip silently if none exist.

6. **Commit**:
   ```
   git add {tickets-dir}/{ID}.md
   git commit -m "{ID}: reopen from {previous-folder}"
   ```

## Finish

Output:
```
{ID} REOPENED

From: {tickets-dir}/{previous-folder}/{ID}.md
To:   {tickets-dir}/{ID}.md
New status: {new-status}
Reason: {reason}

Next: run /ticket-investigate {ID} (if status is open)
      or /ticket-approve {ID} (if status is proposed)
```

## Rules

- Never reopen by copying — always `git mv` so history is clean and there is exactly one file for any given `{ID}`.
- Never delete the historical `## Shipped` / `## Deferred` / `## Closed` sections. The full lifecycle must remain readable.
- If the ticket was shipped and the `branch` field still references the old feature branch, clear the `branch` field — the old branch is merged and gone; the next pass needs a new branch.
