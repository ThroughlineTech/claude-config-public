---
description: '[TKT-XXX ...] [--dry-run] — investigate, approve, and ship tickets sequentially'
argument-hint: '[TKT-XXX ...] [--dry-run]'
---

# Chain Tickets: Investigate → Approve → Ship (Sequential)

Run the full lifecycle — investigate, approve, ship — on a set of tickets one at a time. Each ticket is shipped before the next begins, so later tickets always build on the merged work of earlier ones.

This is the "queue up work and walk away" workflow. One prowl when the whole chain completes (or when something fails).

## Input

Arguments: a list of ticket IDs, OR no arguments.

- `/ticket-chain TKT-026 TKT-027 TKT-028` — operate on exactly these tickets, in this order
- `/ticket-chain 26 27 28` — same thing (bare numbers are expanded; see ID shorthand below)
- `/ticket-chain` — operate on **every** ticket in the active set whose status is `open`, in ID order

**ID shorthand:** Any argument that is a bare number (e.g., `26` or `3`) is resolved to a full ticket ID: read the ticket prefix from `.claude/ticket-config.md`, scan existing ticket files to determine the zero-padding width, and expand (e.g., `26` → `TKT-026`). Full IDs and bare numbers can be mixed freely.

Optional flags:
- `--dry-run` — investigate all tickets but stop before approving any. Useful for reviewing plans before committing to implementation.

## Pre-flight Checks

- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- Read Test, Build, and Deploy commands from the config.
- Working tree must be clean. If dirty, STOP.
- Must be on the main branch. If not, STOP — chain mode ships sequentially to main.
- Determine the main branch name.

## Phase 0: Resolve the ticket set

1. If IDs were given, locate each ticket file in the active set (not in `shipped/`, `deferred/`, `wontfix/`). Any terminal ticket → STOP and report.
2. If no IDs given, list all files at `{tickets-dir}/{PREFIX}*.md` with status `open`.
3. Only accept tickets with status `open` or `proposed`. Reject `in-progress`, `review`, or any terminal status — those are mid-flight.
4. Sort by ID (numeric portion) to ensure deterministic order.

If the resolved set is empty, STOP with "no tickets to chain."

Print the plan before starting:

```
CHAIN PLAN — {N} tickets

  1. TKT-026  "short title"  (open → will investigate + approve + ship)
  2. TKT-027  "short title"  (open → will investigate + approve + ship)
  3. TKT-028  "short title"  (proposed → will approve + ship)

Starting...
```

## Phase 1: Process each ticket sequentially

For each ticket in order:

### Step A: Investigate (if status is `open`)

Run the equivalent of `/ticket-investigate {ID}`:

1. Read the ticket's Description and Acceptance Criteria.
2. Read `CLAUDE.md`, `.claude/ticket-config.md`, and context docs.
3. Deep-dive the relevant code — read every relevant file end-to-end.
4. Write the Investigation, Proposed Solution, and Implementation Plan sections into the ticket.
5. Transition status to `proposed`.

If the investigation finds the ticket is invalid or already fixed, set status to `closed`, report it, and **continue to the next ticket** (don't abort the chain).

### Step B: Risk gate

Read the `Regression Risk` from the Investigation section.

- **`high`**: STOP the entire chain. Do NOT approve or implement this ticket. Report which ticket triggered the gate and why. The chain is intentionally halted — the user needs to review the investigation before proceeding.
- **`low` or `medium`**: continue.

If `--dry-run` was passed, STOP the chain here (after investigating all tickets). Report all investigations and exit.

### Step C: Approve + Implement (if status is `proposed`)

Run the equivalent of `/ticket-approve {ID}`:

1. Create a feature branch from `{main}`: `ticket/{lowercased-id}-{slugified-title}`.
2. Implement the plan step by step. Read before writing. Follow project rules.
3. Write tests following existing conventions.
4. Run Test command — all tests must pass.
5. Run Build command — must be clean.
6. Fill in Files Changed + Test Report sections.
7. Commit each logical unit with `{ID}: ...` messages.
8. Transition status to `review`.

If implementation fails (tests won't pass, build breaks, plan is unworkable):
- Leave the ticket in its current state (`proposed` or `in-progress`).
- Report the failure.
- **STOP the chain.** Do not continue to the next ticket — shipping is sequential, and a failed ticket means later tickets might depend on work that didn't land.

### Step D: Ship

Run the equivalent of `/ticket-ship {ID}`:

1. Rebase onto `origin/{main}`.
2. Run tests + build after rebase.
3. Merge to main with `--no-ff`.
4. Run tests + build on main after merge. If anything fails, `git reset --hard HEAD~1` and STOP the chain.
5. Push to origin.
6. Deploy if a Deploy command is configured.
7. Delete the feature branch.
8. Archive the ticket to `tickets/shipped/` via `git mv`, commit, push.
9. Clean up any worktree/preview for this ticket.

If shipping fails at any point, STOP the chain and report.

### Between tickets

After successfully shipping a ticket, print a progress line:

```
✓ TKT-026 shipped (1/6)  [investigate 45s → implement 2m12s → ship 28s]
```

Then pull latest main and continue to the next ticket.

## Phase 2: Final report + prowl

After all tickets are processed (or the chain stops), print:

```
CHAIN COMPLETE

Requested:  {N} tickets
Shipped:    {n}
Failed:     {ticket ID + reason, if any}
Stopped at: {ticket ID, if chain was halted by risk gate or failure}
Remaining:  {count of unprocessed tickets, if chain stopped early}

Shipped tickets:
  TKT-026  "title"  {merge commit}
  TKT-027  "title"  {merge commit}
  TKT-028  "title"  {merge commit}
```

Send **one** prowl:

- **All succeeded:**
  - Application: `Claude Code: {project-name}`
  - Event: `Chain complete — {N} tickets shipped`
  - Description: list of shipped ticket IDs and titles
  - Priority: `0`

- **Stopped on failure or risk gate:**
  - Application: `Claude Code: {project-name}`
  - Event: `Chain stopped at {ID}`
  - Description: reason + how many shipped before failure
  - Priority: `1`

## Rules

- **Sequential, always.** Never parallelize. Each ticket ships to main before the next starts. This is the entire point — later tickets see earlier changes.
- **High regression risk is a hard stop.** The chain halts, not just that ticket. This is stricter than batch mode (which skips and continues) because chain mode ships — you can't skip a risky ticket and ship the ones after it when they might depend on it.
- **Failures stop the chain.** Unlike batch mode where failures are isolated in worktrees, chain mode operates on main. A failure means the next ticket's context may be wrong.
- **No manual approval step.** The user opted into auto-approval by running `/ticket-chain`. The risk gate (`high` regression risk) is the safety valve.
- **One prowl.** Never per-ticket.
- **Never force push.** Never push broken code. If post-merge tests fail, reset and stop.
- **Invalid/already-fixed tickets don't break the chain.** Close them and keep going — they're a no-op, not a failure.
