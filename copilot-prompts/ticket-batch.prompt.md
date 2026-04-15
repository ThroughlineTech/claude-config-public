---
mode: agent
description: Run multiple tickets in parallel worktrees (investigate → implement → preview)
argument-hint: '[TKT-XXX ...] [--mode=auto|rollup|individual] [--no-preview] [--sequential]'
---

# Batch a Set of Tickets

Run investigate → implement → preview on multiple tickets, each in its own git worktree. Notify the user once when the whole batch is ready.

> **Note on `/ticket-chain` in Copilot:** the Copilot version of `/ticket-chain` is single-ticket only. Use `/ticket-batch` when you need to process multiple tickets together with preview infrastructure and port management. For the full multi-ticket chain experience (dependency graphs, wave execution, consolidated review), use Claude Code's `/ticket-chain`.

## Input

Arguments: a list of ticket IDs, OR no arguments.

- `TKT-014 TKT-015 TKT-016` — operate on exactly these tickets
- `14 15 16` — same (bare numbers are expanded)
- *(no args)* — operate on every ticket in the active set with status `open`

**ID shorthand:** Any bare number is resolved to a full ticket ID: read the prefix from `.claude/ticket-config.md`, scan files to determine zero-padding, expand.

Optional flags:
- `--mode=auto|rollup|individual` — override the project's `Preview mode`.
- `--no-preview` — implement everything but skip preview.
- `--sequential` — force one-at-a-time execution.

## Pre-flight Checks

- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- Read Test, Build, Preview commands, Preview mode, and Preview port base from the config.
- Working tree must be clean. If dirty, STOP.
- Determine the main branch.

## Phase 0: Auto-reap stale worktrees

Walk `.worktrees/ticket-*/`. Resolve each to a ticket ID. Remove the worktree and kill any preview PIDs for tickets in terminal subfolders or not found. (Inline the cleanup logic — do not re-dispatch to `/ticket-cleanup`.)

## Phase 1: Resolve the ticket set

1. If IDs were given, locate each ticket file. Each must be in the active set. Any terminal ticket → STOP and report.
2. If no IDs given, list all `{tickets-dir}/{PREFIX}*.md` files (root only) with status `open`.
3. For each ticket, verify status is `open` (will investigate then implement) or `proposed` (skip investigation, implement only).
4. Reject `in-progress`, `review`, `delegated`, or any terminal status.

If the resolved set is empty, STOP with "no tickets to batch."

## Phase 2: Pre-implement conflict check (static)

For each ticket in the set, read its `Implementation Plan` section and extract file paths mentioned. Intersect the sets pairwise.

If any pair lists overlapping files, print a warning but do NOT block:
```
⚠ Pre-implement conflict check:
    TKT-014 and TKT-015 both plan to touch src/auth.ts
  Proceeding anyway. Post-implement diff check will confirm what actually happened.
```

Tickets with status `open` (no plan yet) are skipped in this check.

## Phase 3: Create worktrees

For each ticket:
1. Branch name: `ticket/{lowercased-id}-{slugified-title}`.
2. If ticket already has a `branch` field and it exists, reuse it. Otherwise create from `{main}`.
3. `git worktree add .worktrees/ticket-{lowercased-id} {branch}` (or `-b {branch} {main}`).
4. Update ticket's `branch` field if empty.

Ensure `.worktrees/` is in `.gitignore` — add it if it isn't.

## Phase 4: Investigate + implement (sequential loop or --sequential)

**Adapted from source:** source spawns parallel subagents via the Agent tool. In Copilot agent mode, process tickets sequentially in one session unless the Copilot environment supports parallel agent calls.

For each ticket (in input order unless reordered by `--sequential`):

> Working on ticket {ID} in worktree at `.worktrees/ticket-{lowercased-id}/`:
>
> 1. If status is `open`: run the full investigation — read the ticket, explore the codebase, fill in Investigation, Proposed Solution, Implementation Plan. Transition to `proposed`.
> 2. If `Regression Risk: high` is found, STOP this ticket. Leave status at `proposed`. Report "high regression risk — needs human approval."
> 3. If status is `proposed`: implement the plan in the worktree (without creating a new branch — the worktree is already on the correct branch). Write tests, run `{Test}` and `{Build}` from ticket-config. Fill in Files Changed + Test Report. Commit with `{ID}: ...` messages.
> 4. On success: transition status to `review`.
> 5. On failure: leave the ticket in a consistent state and report the failure. Do NOT ship broken code.
>
> All work happens in the worktree. Do NOT touch the main repo directory.

After each ticket completes, print a one-line progress summary:
```
✓ TKT-014 (1/3) — implemented, status: review, tests: 12 added
✗ TKT-015 (2/3) — failed: build error in src/auth.ts
⏸ TKT-020 (3/3) — paused: high regression risk
```

### Copy updated ticket files back to the main working directory

After all tickets are processed, for each that reached `proposed` or `review` status, copy `.worktrees/ticket-{lowercased-id}/tickets/{ID}.md` over `tickets/{ID}.md` in the main working directory. Stage and commit: `ticket-batch: update {N} tickets with investigation results`.

## Phase 5: Post-implement conflict check (dynamic)

For each ticket that reached `review`, run `git diff {main}...{branch} --name-only` and collect file lists. Intersect pairwise.

Build a `conflict_notes` dictionary: for each ticket, list which other tickets also touched the same files. Attach to the preview output.

## Phase 6: Preview

**Mode selection:** `--mode` flag if given, else `Preview mode` from config, else `individual`. Skip entirely if `--no-preview` was passed or `## Preview profiles` is empty.

If any profile in the batch has `Sequential: true`, force `individual` mode.

Group tickets by their `app:` profile. Decide preview mode per profile group.

### Mode: `individual`

For each `review`-status ticket, launch a preview:
- Port = `{Preview port base} + {numeric-id}`
- Worktree at `.worktrees/ticket-{lowercased-id}/`
- Record PID + meta in `.preview.pid` and `.preview.meta`
- If `Sequential: true`, launch one at a time (ask for confirmation between each).

### Mode: `rollup`

1. Create a scratch branch from `{main}`: `git checkout -b batch-preview-{YYYY-MM-DD-HHMM}`.
2. Merge each successful ticket branch in ID order: `git merge ticket/{...} --no-ff`.
3. If any merge hits a conflict:
   - **`rollup` mode (forced):** abort, reset, delete, FAIL the batch preview with a clear report.
   - **`auto` mode:** abort, reset, delete, fall back to `individual` mode with a note.
4. On success: launch the Preview command once on the scratch branch. Port = `{Preview port base} + 999`. Record PID + meta.

### Mode: `auto`

Try `rollup` first. On any conflict, fall back to `individual`.

## Phase 7: Final report

**One** prowl/notification at the end — never per-ticket.

- Application: `ticket-batch`
- Event: `Batch ready — {N} tickets`
- Description: compact summary of what's previewable and where. Include counts: `{n} ready, {m} high-risk paused, {k} failed`.
- Priority: `1` (high) if there are any failures, `0` otherwise.
- Use Prowl if available (see global CLAUDE.md). Otherwise print prominently in the conversation.

Terminal output:
```
BATCH COMPLETE

Requested:  {N} tickets
Ready:      {n} → status review
Paused:     {m} → status proposed (high regression risk, needs manual approval)
Failed:     {k} → see details below

Preview mode: {mode}

{if rollup:}
Rollup preview: http://localhost:3999   (branch: batch-preview-{timestamp})
Includes: TKT-014, TKT-015, TKT-016

{if individual:}
Previews:
  TKT-014  http://localhost:3014   (also touches src/auth.ts with TKT-015)
  TKT-015  http://localhost:3015   (also touches src/auth.ts with TKT-014)

Conflict notes:
  TKT-014 ↔ TKT-015: both modified src/auth.ts — ship order matters

Paused (high risk):
  TKT-020  regression risk: high — run /ticket-approve TKT-020 after reviewing

Failed:
  TKT-022  tests failed: 3 regressions in auth_test.ts
    Worktree left at .worktrees/ticket-tkt-022 for inspection

Next:
  Ship:              /ticket-ship TKT-014
  Defer regression:  /ticket-defer {ID} {reason}
  Stop a preview:    /ticket-cleanup {ID}
  Stop everything:   /ticket-cleanup --all
```

## Rules

- **High regression risk is a hard manual gate.** If investigation writes `Regression Risk: high`, do NOT auto-implement that ticket. Pause at `proposed`.
- **Conflict checks never block.** They annotate. You decide.
- **One notification.** Never per-ticket.
- **Never ship from batch mode.** Batch ends at preview. Shipping is an explicit per-ticket decision.
- **Failures leave the worktree intact** for post-mortem. Clean up with `/ticket-cleanup` when done.

## Compatibility Notes

- **Parallel subagents → sequential loop:** source spawns parallel investigation/implementation subagents via the Agent tool (one per ticket). In Copilot agent mode this is adapted to a sequential loop. All output and behavioral logic is identical; only wall-clock time differs (sequential is slower for large batches).
- **Prowl notification → conditional:** source always prowls at the end. In Copilot agent mode, Prowl is used if the global CLAUDE.md API key is accessible; otherwise the summary is printed prominently in the conversation.
