---
description: '[TKT-XXX ...] [--dry-run|--sequential|--no-ship] — smart investigate + implement + ship with dependency detection'
argument-hint: '[TKT-XXX ...] [--dry-run|--sequential|--no-ship]'
---

# Chain Tickets: Smart Parallel Investigation → Wave Execution → Ship

The "queue up work and walk away" command. Investigates all tickets in parallel, detects dependencies between them, computes execution waves, implements independent tickets in parallel worktrees within each wave, ships sequentially, then re-investigates dependent tickets against the updated codebase before starting the next wave. One prowl when done.

This subsumes both the old sequential chain and parallel batch workflows. Independent tickets get parallelized automatically; dependent tickets get sequenced automatically. You don't have to think about it.

## Input

Arguments: a list of ticket IDs, OR no arguments.

- `/ticket-chain TKT-026 TKT-027 TKT-028` — operate on exactly these tickets
- `/ticket-chain 26 27 28` — same thing (bare numbers are expanded; see ID shorthand below)
- `/ticket-chain` — operate on **every** ticket in the active set whose status is `open`, in ID order

**ID shorthand:** Any argument that is a bare number (e.g., `26` or `3`) is resolved to a full ticket ID: read the ticket prefix from `.claude/ticket-config.md`, scan existing ticket files to determine the zero-padding width, and expand (e.g., `26` → `TKT-026`). Full IDs and bare numbers can be mixed freely.

Optional flags:
- `--dry-run` — investigate all tickets in parallel, show the dependency graph + wave plan, stop. No implementation, no shipping. Useful for reviewing plans and the execution strategy before committing.
- `--sequential` — force strict sequential processing (no parallelism). Each ticket is investigated, implemented, and shipped one at a time in the order given. This is the escape hatch when you don't trust dependency detection or want maximum predictability.
- `--no-ship` — investigate + implement in waves but stop before shipping. Leaves all tickets at `review` status with branches ready. Useful for review-heavy projects where you want to inspect everything before any merges.

## Pre-flight Checks

- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- Read Test, Build, and Deploy commands from the config.
- Working tree must be clean. If dirty, STOP.
- Must be on the main branch. If not, STOP — chain mode ships to main.
- Determine the main branch name.

## Phase 0: Resolve the ticket set + reap stale worktrees

1. Run the `/ticket-cleanup` reaper logic inline: walk `.worktrees/ticket-*/`, remove worktrees + kill preview PIDs for any ticket whose file lives in a terminal subfolder or doesn't exist.
2. If IDs were given, locate each ticket file in the active set (not in `shipped/`, `deferred/`, `wontfix/`). Any terminal ticket → STOP and report.
3. If no IDs given, list all files at `{tickets-dir}/{PREFIX}*.md` with status `open`.
4. Only accept tickets with status `open` or `proposed`. Reject `in-progress`, `review`, or any terminal status — those are mid-flight.
5. Sort by ID (numeric portion) to ensure deterministic order. **Preserve the user's original argument order as the tiebreaker** for cycle resolution (see Phase 2).

If the resolved set is empty, STOP with "no tickets to chain."

Ensure `.worktrees/` is in `.gitignore` — add it if it isn't.

## Phase 1: Investigate all (parallel)

Spawn one subagent per `open`-status ticket using the Agent tool, **in parallel** (a single message with multiple Agent tool calls). Tickets already at `proposed` skip this phase.

Each investigation subagent gets a prompt like:

> You are investigating ticket {ID}. Your job is to explore the codebase and write a thorough investigation + implementation plan into the ticket file.
>
> 1. Read the ticket's Description and Acceptance Criteria.
> 2. Read `CLAUDE.md`, `.claude/ticket-config.md`, and all context docs listed in the config.
> 3. Deep-dive the relevant code — read every relevant file end-to-end. Map call chains. Identify interfaces, types, and contracts.
> 4. Write into the ticket file:
>    - **Investigation**: what you found, with specific file paths and line numbers. Root cause (for bugs) or architectural fit (for features). Regression risk assessment.
>    - **Proposed Solution**: clear description of approach, why this over alternatives, tradeoffs.
>    - **Implementation Plan**: numbered checklist of specific steps. **Each step must be precise enough that a different engineer with no context beyond this ticket file could implement it.** Each step must name the file, the function/component, and exactly what changes. No vague steps like "add a button" — specify where, what kind, what it does, what it connects to.
>    - **Dependencies**: list any other ticket IDs from the current batch that **must be implemented and shipped before this ticket** for the implementation to be correct. For each dependency, write one line explaining why. **Err on the side of declaring a dependency.** If two tickets touch the same file, or one ticket creates/modifies something the other reads or extends, declare the dependency. When in doubt, declare it — false positives only cost time, false negatives risk broken code. If no dependencies, write "None."
> 5. Transition status to `proposed`.
> 6. If the ticket is invalid or already fixed, set status to `closed` with explanation.
>
> Report back: regression risk level, dependency list, files the plan touches.

### Copy investigations back to the main working directory

After all investigation subagents complete, for each ticket that reached `proposed` or `closed` status, copy the ticket file from the investigation subagent's output back to `tickets/{ID}.md` in the main working directory. Stage and commit: `ticket-chain: investigate {N} tickets`.

### Risk gate

For each investigated ticket, read the `Regression Risk`:
- **`high`**: remove this ticket from the chain. It requires manual review. Add it to the "paused" list in the final report.
- **`low` or `medium`**: keep in the chain.

For tickets the investigation found invalid/already-fixed (now `closed`): remove from the chain, add to the report. These are no-ops, not failures.

If `--dry-run` was passed, print the dependency graph and wave plan (see Phase 2), then STOP.

## Phase 2: Build the dependency graph + compute waves

### Collect dependencies

For each ticket remaining in the chain, read two things:

1. **Declared dependencies** from the `## Dependencies` section — the ticket IDs the investigator explicitly listed.
2. **File overlap heuristic** — extract all file paths from each ticket's `## Implementation Plan`. For each pair of tickets, if their file sets intersect, treat the one that appears *later* in the user's original argument order as depending on the *earlier* one. This is the conservative/overdetection heuristic: overlapping files → dependency, user order = tiebreaker for direction.

Merge both sources. The final dependency set for each ticket is the union of declared + heuristic dependencies.

### Detect and resolve cycles

If the graph contains cycles (A depends on B, B depends on A), **collapse each cycle into a sequential sub-chain** using the user's original argument order as the tiebreaker. Do not error out. Do not ask the user.

Example: if TKT-002 and TKT-003 have a mutual dependency and the user listed 002 before 003, then 003 depends on 002 (not the reverse). Drop the 002→003 edge.

### Compute waves

Topological sort the DAG. Group tickets into waves:
- **Wave 1**: all tickets with no unresolved dependencies (in-degree 0).
- **Wave 2**: all tickets whose dependencies are entirely in wave 1.
- **Wave N**: all tickets whose dependencies are entirely in waves 1 through N-1.

Print the execution plan:

```
CHAIN PLAN — {N} tickets ({W} waves)

Dependency graph:
  TKT-003 depends on TKT-002 (extends auth middleware created by 002)
  TKT-007 depends on TKT-006 (consumes API endpoint added by 006)
  TKT-002 ↔ TKT-003 (cycle resolved: 002 before 003 per user order)

Execution plan:
  Wave 1 (parallel): TKT-001, TKT-002, TKT-004, TKT-005, TKT-006
  Wave 2 (parallel): TKT-003, TKT-007  [will re-investigate after wave 1 ships]

Proceeding...
```

If all tickets are independent (one wave), note it:

```
CHAIN PLAN — 7 tickets (1 wave — all independent)

No dependencies detected. All tickets will be implemented in parallel and shipped sequentially.

Proceeding...
```

## Phase 3: Execute waves

For each wave, in order:

### Step A: Create worktrees

For each ticket in this wave:
1. Branch name: `ticket/{lowercased-id}-{slugified-title}`.
2. If the ticket already has a `branch` field and that branch exists, reuse it. Otherwise create from `{main}`.
3. `git worktree add .worktrees/ticket-{lowercased-id} {branch}` (or `-b {branch} {main}`).
4. Update the ticket's `branch` field if empty.

### Step B: Re-investigate (waves 2+ only)

For tickets in wave 2 and later, the codebase has changed since the original investigation (earlier waves shipped). Their original plans may be stale.

Spawn one subagent per ticket in this wave, **in parallel**, with a re-investigation prompt:

> You are re-investigating ticket {ID}. This ticket was originally investigated earlier, but tickets it depends on have since been shipped to main. The codebase has changed.
>
> 1. Pull the latest main into your worktree.
> 2. Re-read the files that are relevant to this ticket's implementation plan.
> 3. Review the original Investigation, Proposed Solution, and Implementation Plan in the ticket file.
> 4. **Update** all three sections to reflect the current state of the codebase. The plan may need significant revision if the dependency shipped code that changes the approach, or minor tweaks if the dependency only touched shared files incidentally.
> 5. Update the Dependencies section: mark resolved dependencies as "[shipped]".
> 6. Keep the Implementation Plan to the same specificity standard: every step names the file, function, and exact change.

Copy updated ticket files back to main working directory. Stage and commit: `ticket-chain: re-investigate {N} tickets (wave {W})`.

Re-check regression risk. If any re-investigated ticket now shows `high`, remove it from the chain and add to the paused list.

### Step C: Implement (parallel within wave)

Spawn one subagent per ticket in this wave, **in parallel** (single message with multiple Agent tool calls).

Each implementation subagent gets a prompt like:

> You are implementing ticket {ID} in an isolated git worktree at `.worktrees/ticket-{lowercased-id}/`. The worktree is already on the correct feature branch.
>
> 1. Read the ticket's Implementation Plan. Follow it step by step.
> 2. Read before writing. Follow project rules from `CLAUDE.md`.
> 3. Write tests following existing conventions.
> 4. Run `{Test}` — all tests must pass. Fix failures immediately.
> 5. Run `{Build}` — must be clean.
> 6. Fill in the Files Changed and Test Report sections in the ticket file.
> 7. Commit each logical unit with `{ID}: ...` messages.
> 8. Transition status to `review`.
> 9. On failure: leave the ticket in whatever state makes sense, report the failure. Do NOT ship broken code.
>
> All work happens in the worktree. Do NOT touch the main repo directory.
>
> Report back: branch, commit count, files changed, test count, build status, success/failure.

Collect results. Track successes, failures.

Copy updated ticket files back to main. Stage and commit: `ticket-chain: implement {N} tickets (wave {W})`.

### Step D: Ship (sequential within wave)

If `--no-ship` was passed, skip this step for all waves.

For each successfully implemented ticket in this wave, **in ID order**:

1. Ensure we're on `{main}` and pull latest.
2. Rebase the ticket's branch onto `origin/{main}`.
3. Run tests + build after rebase.
4. Merge to main with `--no-ff -m "Merge {ID}: {title}"`.
5. Run tests + build on main after merge.
   - If anything fails: `git reset --hard HEAD~1`. **This ticket failed.** Add it to the failed list. **Continue to the next ticket in this wave** — the failure is isolated to this ticket's branch, and other tickets in this wave are independent (that's why they're in the same wave).
6. Push to origin.
7. Deploy if configured.
8. Delete the feature branch.
9. Archive to `tickets/shipped/` via `git mv`, commit, push.
10. Clean up the worktree + any preview processes.

Print progress after each ship:

```
✓ TKT-001 shipped (1/7)  [implement 2m12s → ship 28s]
```

### Between waves

After all tickets in a wave are shipped (or failed), print a wave summary:

```
Wave 1 complete: 4/5 shipped, 1 failed (TKT-004: tests failed after merge)
Starting wave 2 (2 tickets, re-investigating against updated codebase)...
```

Pull latest main and proceed to the next wave.

**If a failed ticket in wave N has dependents in wave N+1:** remove the dependents from the chain. They can't proceed because their dependency didn't ship. Add them to the report as "skipped — dependency TKT-XXX failed."

## Phase 4: Final report + prowl

```
CHAIN COMPLETE

Requested:  {N} tickets
Shipped:    {n} in {W} waves
Paused:     {p} (high regression risk — needs manual review)
Failed:     {f} (see details below)
Skipped:    {s} (dependency failed)
Invalid:    {i} (closed during investigation)

Wave 1 (parallel):
  ✓ TKT-001  "title"  {merge commit}
  ✓ TKT-002  "title"  {merge commit}
  ✗ TKT-004  "title"  FAILED: tests failed after merge (branch left at ticket/tkt-004-...)
  ✓ TKT-005  "title"  {merge commit}
  ✓ TKT-006  "title"  {merge commit}

Wave 2 (parallel, re-investigated):
  ✓ TKT-003  "title"  {merge commit}
  ✓ TKT-007  "title"  {merge commit}

Paused (high risk):
  TKT-020  regression risk: high — manual approval needed
    Run /ta 20 after reviewing the investigation

Failed:
  TKT-004  tests failed after merge: 3 regressions in auth_test.ts
    Branch left at ticket/tkt-004-... for inspection
    Worktree at .worktrees/ticket-tkt-004/

Skipped (dependency failed):
  (none in this run)

Next:
  Inspect failures:   cd .worktrees/ticket-tkt-004 && git log --oneline
  Retry a ticket:     /tch 4
  Defer failures:     /td 4 {reason}
  Review a paused one: /ti 20  (then /ta 20 if it looks good)
  Clean up:           /tcl --all
```

Send **one** prowl:

- **All succeeded:**
  - Application: `Claude Code: {project-name}`
  - Event: `Chain complete — {n} shipped in {W} waves`
  - Description: list of shipped ticket IDs. If any paused/failed, mention counts.
  - Priority: `0`

- **Any failures or stops:**
  - Application: `Claude Code: {project-name}`
  - Event: `Chain done — {n} shipped, {f} failed`
  - Description: which tickets failed and why (brief). Which were paused.
  - Priority: `1`

## `--sequential` mode

When `--sequential` is passed, skip all parallelism and dependency detection. Process tickets one at a time in the order given:

For each ticket:
1. Investigate (if `open`)
2. Risk gate — `high` stops the entire chain
3. Implement
4. Ship

This is the old `/ticket-chain` behavior. Use it when:
- The project has flaky tests that fail under parallel execution
- You want maximum predictability
- You're debugging a specific ordering issue

## Rules

- **Bias toward overdetection of dependencies.** A false dependency costs time (ticket gets sequenced instead of parallelized). A missed dependency risks shipping broken code. Investigation prompts explicitly instruct agents to err on the side of declaring dependencies. The file-overlap heuristic adds a second layer of conservative detection on top.
- **Cycles are resolved, never rejected.** User argument order is the tiebreaker. The system always produces a valid execution plan.
- **High regression risk removes the ticket from the chain, doesn't stop it.** Unlike `--sequential` mode where high risk halts everything, smart mode can safely skip a risky ticket because other tickets in the wave are independent. The risky ticket is reported for manual review.
- **Failures within a wave don't stop other tickets in that wave** (they're independent by construction). But failures **do** cascade: if TKT-002 fails, anything in later waves that depends on TKT-002 is skipped.
- **Re-investigation between waves is mandatory.** The codebase changed. The original plan is stale. Skipping re-investigation to save tokens is not worth the risk of implementing against outdated assumptions.
- **Ship sequentially, always.** Even within a wave of independent tickets, shipping (merge to main) happens one at a time. Merges must be tested against the true state of main, which changes after each ship.
- **No manual approval step.** The user opted into auto-approval by running `/ticket-chain`. The risk gate and post-merge test failure are the safety valves.
- **One prowl.** Never per-ticket, never per-wave.
- **Never force push.** Never push broken code. If post-merge tests fail, reset and skip that ticket.
- **Invalid/already-fixed tickets don't break the chain.** Close them and keep going.
- **Worktree cleanup happens on ship.** Successfully shipped tickets get their worktrees removed immediately. Failed tickets keep their worktrees for inspection. The next `/tcl` or subsequent chain's auto-reap cleans up the rest.
