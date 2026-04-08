---
description: '[TKT-XXX ...] [--mode=auto|rollup|individual] [--no-preview] — run multiple tickets in parallel worktrees'
argument-hint: '[TKT-XXX ...] [--mode=auto|rollup|individual] [--no-preview]'
---

# Batch a Set of Tickets

Run investigate → auto-approve → implement → preview on multiple tickets in parallel, each in its own git worktree. Notify the user once when the whole batch is ready (via the push-notification channel configured in `~/.claude/CLAUDE.md`, if any). This is the workflow for queuing up work and coming back later to smoke-test everything at once.

## Input

Arguments: a list of ticket IDs, OR no arguments.

- `/ticket-batch TKT-014 TKT-015 TKT-016` — operate on exactly these tickets
- `/ticket-batch` — operate on **every** ticket in the active set whose status is `open` (i.e. "do all queued work")

Optional flags:
- `--mode=auto|rollup|individual` — override the project's `Preview mode`. Default: whatever `.claude/ticket-config.md` says.
- `--no-preview` — implement everything but skip the preview step (you just want the branches built).
- `--sequential` — force one-at-a-time execution even on projects where parallel is fine.

## Pre-flight Checks

- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- Read Test, Build, and Preview commands + Preview mode + Preview port base from the config.
- Working tree must be clean. If dirty, STOP — batch mode creates worktrees which requires a clean base.
- Determine the main branch.

## Phase 0: Auto-reap stale worktrees

Before anything else, run the `/ticket-cleanup` reaper logic inline: walk `.worktrees/ticket-*/`, resolve each to a ticket ID, and remove the worktree + kill any preview PID for any ticket whose file lives in a terminal subfolder or doesn't exist. This is the ambient self-healing — it means previous crashed batches don't accumulate.

## Phase 1: Resolve the ticket set

1. If IDs were given, **locate each ticket file**. Each must be in the active set (not in `shipped/`, `deferred/`, `wontfix/`). Any terminal ticket → STOP and report.
2. If no IDs given, list all files at `{tickets-dir}/{PREFIX}*.md` (root only, not recursive) with status `open` from the frontmatter.
3. For each ticket, verify status is one of: `open` (most common — we'll investigate then implement) or `proposed` (investigation already done — we'll skip straight to implement).
4. Reject `in-progress`, `review`, `delegated`, or any terminal status — these are mid-flight and should not be batched.

If the resolved set is empty, STOP with "no tickets to batch."

## Phase 2: Pre-implement conflict check (static)

For each ticket in the set, read its `Implementation Plan` section and extract any file paths it mentions (grep for file-like tokens, backtick-quoted paths, etc.). This is best-effort — the plan's format isn't rigid. Intersect the sets pairwise.

If any pair of tickets lists overlapping files, print a warning but **do not block**:

```
⚠ Pre-implement conflict check:
    TKT-014 and TKT-015 both plan to touch src/auth.ts
    TKT-015 and TKT-017 both plan to touch src/session.ts
  Proceeding anyway. Post-implement diff check will confirm what actually happened.
```

Tickets with status `open` don't have an Implementation Plan yet — skip them in this check (the plan will exist after investigation).

## Phase 3: Create worktrees

For each ticket in the set:

1. Determine the branch name: `ticket/{lowercased-id}-{slugified-title}` (same scheme `/ticket-approve` uses).
2. If the ticket already has a `branch` field and that branch exists, reuse it. Otherwise create it from `{main}`.
3. Create the worktree: `git worktree add .worktrees/ticket-{lowercased-id} {branch}` (or `-b {branch} {main}` if the branch doesn't exist yet).
4. Update the ticket's `branch` field if it was empty.

`.worktrees/` should be in `.gitignore` — add it if it isn't.

## Phase 4: Investigate + implement (parallel subagents)

Spawn one subagent per ticket using the Agent tool, **in parallel** (a single message with multiple Agent tool calls), unless `--sequential` was passed.

Each subagent gets a prompt roughly like:

> You are working on ticket {ID} in an isolated git worktree at `.worktrees/ticket-{lowercased-id}/`. Your job: bring the ticket from its current status to `review`.
>
> 1. If status is `open`: run the equivalent of `/ticket-investigate {ID}` — read the ticket, explore the codebase, fill in Investigation, Proposed Solution, Implementation Plan in the ticket file. Then auto-transition to `proposed` and continue.
> 2. If the ticket's `## Investigation` section records `Regression Risk: high`, STOP and leave status at `proposed`. Do NOT implement. Report "high regression risk — needs human approval."
> 3. If status is `proposed` (including just-transitioned): run the equivalent of `/ticket-approve {ID}` **without creating a new branch** — the worktree is already on the right branch. Implement the plan, write tests, run `{Test}` and `{Build}` from ticket-config, fill in Files Changed + Test Report sections, commit each logical unit with `{ID}: ...` messages.
> 4. On successful build + tests, transition status to `review`. Report back: branch, commit count, files changed, test count, build status.
> 5. On failure (tests fail, build fails, plan is impossible, etc.): leave the ticket in whatever state makes sense (`proposed` if investigation found the plan unworkable, `in-progress` if implementation partially happened), and report the failure. Do NOT ship broken code.
>
> All work happens in the worktree. Do NOT touch the main repo directory.

Collect each subagent's result. Track:
- Which tickets succeeded to `review`
- Which tickets stopped at `proposed` (high regression risk — manual gate)
- Which tickets failed outright (with reason)

## Phase 5: Post-implement conflict check (dynamic)

For each ticket that successfully reached `review`, run `git diff {main}...{branch} --name-only` and collect the file lists. Intersect them pairwise.

Build a `conflict_notes` dictionary: for each ticket, a list of "also touched by TKT-XXX" strings. This gets attached to the preview output so you know which combinations to inspect carefully.

## Phase 6: Preview

**Mode selection:**
- `--mode` flag if given, else `Preview mode` from config, else `individual`.
- If the `## Preview profiles` section is empty or `--no-preview` was passed, skip this entire phase.
- If **any** component of **any** profile used by tickets in this batch has `Sequential: true` (e.g. iOS simulator), force `individual` mode — rollup makes no sense when previews can't coexist.

**Group tickets by profile.** Each `review`-status ticket has an `app:` field identifying its profile. Group the batch by profile, because:
- Rollup only makes sense *within* a profile (you can't merge server-only tickets with iOS-only tickets into one preview).
- Sequential profiles have to be handled differently from parallel ones.

For each profile group, decide mode independently: a batch with 3 server tickets and 2 iOS tickets will run the server group in rollup/parallel mode and the iOS group sequentially.

### Mode: `individual`

For each `review`-status ticket in the batch, launch a preview exactly as `/ticket-preview {ID}` would:
- Port = `{Preview port base} + {numeric-id}`
- Worktree at `.worktrees/ticket-{lowercased-id}/`
- Record PID + meta in `.worktrees/ticket-{lowercased-id}/.preview.pid` and `.preview.meta`
- If `Preview sequential: true`, launch them one at a time, waiting for user confirmation between each (AskUserQuestion: "done with TKT-014 preview? ready for TKT-015?").

### Mode: `rollup`

1. Create a scratch branch from `{main}`: `git checkout {main} && git checkout -b batch-preview-{YYYY-MM-DD-HHMM}`.
2. Merge each successful ticket branch into the scratch branch in ID order: `git merge ticket/{...} --no-ff -m "batch-preview: include {ID}"`.
3. If any merge hits a conflict:
   - **`rollup` mode (forced):** abort the merge, reset the scratch branch, delete it, FAIL the batch preview with a clear report of which ticket conflicted with which. Do not fall back.
   - **`auto` mode:** abort, reset, delete the scratch branch, and fall through to `individual` mode. Include a note in the final output: "rollup failed at TKT-XXX (conflicts with TKT-YYY); fell back to individual previews."
4. On successful rollup: launch the `Preview command` once on the scratch branch. Port = `{Preview port base} + 999` (reserved for rollups). Record PID + meta in `.worktrees/batch-preview-{timestamp}/.preview.pid`.

### Mode: `auto`

Try `rollup` first. On any merge conflict, fall back to `individual` as described above.

## Phase 7: Final notification + report

**One** push notification at the end of the batch — never per-ticket. Use the push-notification channel configured in `~/.claude/CLAUDE.md`; skip silently if none is configured.

- Application: `Claude Code: ticket-batch`
- Event: `Batch ready — {N} tickets`
- Description: a compact summary of what's previewable and where (URLs, ports, simulator notes). Include counts: `{n} ready for review, {m} high-risk paused at proposed, {k} failed`.
- Priority: `1` (high) if there are any failures, `0` otherwise.

Terminal output:

```
BATCH COMPLETE

Requested:  {N} tickets
Ready:      {n} → status review
Paused:     {m} → status proposed (high regression risk, needs manual approval)
Failed:     {k} → see details below

Preview mode: {auto→rollup | auto→individual (fell back) | rollup | individual | skipped}

{if rollup:}
Rollup preview: http://localhost:3999   (combined branch: batch-preview-{timestamp})
Includes: TKT-014, TKT-015, TKT-016

{if individual:}
Previews:
  TKT-014  http://localhost:3014   (also touches src/auth.ts with TKT-015)
  TKT-015  http://localhost:3015   (also touches src/auth.ts with TKT-014)
  TKT-016  http://localhost:3016

Conflict notes:
  TKT-014 ↔ TKT-015: both modified src/auth.ts
    → they may conflict at ship time; ship order matters, or defer one

Paused (high risk):
  TKT-020  regression risk: high — manual approval needed
    Run /ticket-approve TKT-020 after reviewing the investigation

Failed:
  TKT-022  tests failed after implementation: 3 regressions in auth_test.ts
    Worktree left at .worktrees/ticket-tkt-022 for inspection

Next:
  Ship the good ones:   /ticket-ship TKT-014
  Defer regressions:    /ticket-defer {ID} {reason}   (also auto-rebuilds rollup)
  Stop a preview:       /ticket-cleanup {ID}
  Stop everything:      /ticket-cleanup --all
```

## Rules

- **Parallelism via subagents, not serialism.** Spawn all implementation agents in a single message with multiple Agent tool calls. The main thread only orchestrates. This keeps the main context small and lets real parallelism happen on build/test I/O.
- **High regression risk is a hard manual gate.** If an investigation writes `Regression Risk: high`, the batch must NOT auto-implement that ticket. It pauses at `proposed` and the final report calls it out.
- **Conflict checks never block.** They annotate. You decide.
- **One notification.** Never per-ticket.
- **Never ship from batch mode.** Batch ends at preview. Shipping remains an explicit per-ticket decision (`/ticket-ship`).
- **Worktree cleanup happens on terminal transitions, not on batch end.** When you later run `/ticket-ship TKT-014`, that command tears down the TKT-014 worktree and preview as a side effect. Same for `/ticket-defer` and `/ticket-close`. So the batch leaves worktrees + previews live; they get reaped as you decide each ticket's fate.
- **If `/ticket-defer` or `/ticket-close` runs while a rollup preview is live**, that command must also rebuild the rollup (merge the remaining successful tickets into a new scratch branch, relaunch the preview). This is the "dynamic rollup" behavior.
- **Failures leave the worktree intact** for post-mortem. The next `/ticket-cleanup` or subsequent batch's auto-reap will clean them up once the ticket transitions to a terminal state (or you manually `/ticket-cleanup {ID}`).
