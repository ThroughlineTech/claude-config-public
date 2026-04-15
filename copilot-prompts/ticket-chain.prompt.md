---
mode: agent
description: Investigate, implement, and optionally ship a single ticket end-to-end
argument-hint: 'TKT-XXX [--ship] [--dry-run]'
---

# Chain a Ticket: Investigate → Implement → Review

Single-ticket orchestration: investigate (if needed), implement, run the review checklist, and optionally ship. The Copilot target for this command is one ticket at a time in a single agent session.

For multi-ticket parallel workflows, use `/ticket-batch` or `/ticket-chain` in Claude Code (which supports parallel worktrees via the Agent tool).

## Input

Argument: one ticket ID. Optional flags:

- `--ship` — after implementation, automatically continue through ship steps without pausing for a review checklist.
- `--dry-run` — investigate only; show the implementation plan and stop. No implementation, no shipping.

**ID shorthand:** If the argument is a bare number (e.g., `26` or `3`), resolve it to a full ticket ID: read the ticket prefix from `.claude/ticket-config.md`, scan existing ticket files to determine zero-padding width, and expand (e.g., `26` → `TKT-026`).

## Pre-flight Checks

- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- Read Test, Build, and Deploy commands from the config.
- Determine the main branch: read `Main branch` from `.claude/ticket-config.md` if present, otherwise fall back to `git symbolic-ref refs/remotes/origin/HEAD`. If the result is `master`, warn and suggest `/ticket-install`.
- Working tree must be clean. If dirty, STOP.
- Must be on the main branch. If not, STOP — chain mode ships to main.
- Locate the ticket file at `{tickets-dir}/{ID}.md`. If it's in a terminal subfolder, STOP and tell the user to run `/ticket-reopen {ID}` first.
- Ticket status must be `open` or `proposed`. Reject `in-progress`, `review`, or any terminal status.

## Plan-drift check

Before starting implementation, if the ticket is already `proposed` (has an existing investigation), briefly verify the Implementation Plan still matches the current codebase state:
- Spot-check 2–3 key files named in the plan.
- If significant drift is detected (files moved, interfaces changed, referenced code deleted), re-run the investigation phase before proceeding. Note the re-investigation in the output.

## Phase 1: Investigate (if status is `open`)

If the ticket's status is `open`, run the full investigation:

1. Read `CLAUDE.md` (if it exists) for project rules.
2. Read `.claude/ticket-config.md` for stack info and context docs.
3. Read each "Context docs" path listed in the config.
4. Deep-dive relevant code: read every relevant file end-to-end. Map call chains. Identify interfaces, types, and contracts.
5. Write into the ticket file:
   - **Investigation:** what you found, with specific file paths and line numbers. Root cause (bugs) or architectural fit (features). Regression risk assessment.
   - **Proposed Solution:** clear description of approach, why this over alternatives, tradeoffs.
   - **Implementation Plan:** numbered checklist of specific steps. Each step must name the file, function/component, and exactly what changes. No vague steps.
6. Update status to `proposed`, update date.

If `--dry-run` was passed, output the plan summary and STOP here.

Print a summary:
```
{ID} investigated — risk: {low|medium|high}, files: {N}, steps: {N}
```

## Phase 2: Implement

If regression risk is `high`, STOP. Report: "Regression risk is high — manual review required before implementation. Review the investigation in {ticket path}."

1. Ensure we're on the main branch and it's up to date: `git checkout {main} && git pull`
2. Create feature branch: `git checkout -b ticket/{lowercased-id}-{slugified-title}`
3. Update ticket: set `branch` field, status to `in-progress`, update date.

Work through the Implementation Plan step by step:
- Read before writing. Follow project rules from `CLAUDE.md`.
- Write clean code following existing patterns.
- Check off each plan item as you complete it.
- Add tests for every new function/method (happy path, error cases, edge cases).
- Run the Test command. Every test must pass. Fix failures immediately.
- Run the Build command. Must be clean.
- Run Lint if configured.

Update the ticket:
- **Files Changed section:** list every file created/modified with a one-line description.
- **Test Report section:** tests added, tests passing, build status, any warnings.

Commit: `git add {specific files}` (NOT `-A`), then `git commit -m "{TKT-ID}: {title}"`. Use multiple commits for multiple logical units.

Update ticket status to `review`.

Print a summary:
```
{ID} implemented — branch: {branch}, commits: {N}, files: {N}, tests: {N}, build: clean
```

## Phase 3: Review checklist (default mode, no `--ship`)

If `--ship` was NOT passed, generate a human verification checklist:

Run automated checks on the feature branch:
1. Tests: run the Test command. Capture pass/fail + counts.
2. Build: run the Build command. Capture pass/fail.
3. Lint: run if configured. Capture pass/fail + warning count.
4. Branch rebased on main: `git merge-base --is-ancestor origin/{main} HEAD`.
5. No merge conflicts: verify clean merge with main.

Write the `### Automated Checks` section into the ticket's `## Verification Checklist` area.

Generate a human-testable checklist based on the ticket's Acceptance Criteria, Implementation Plan, and actual changes:
- Each item must be specific, observable, and independently verifiable.
- Structure: Setup → Core Functionality → Edge Cases → Regression Checks → Verdict.

Present the checklist and output:
```
{ID} Ready for Review

Branch: {branch}
Automated checks: {M}/{M} passed (or: {N} failed)

## Verification Checklist
{checklist}

When verified, run /ticket-ship {ID} to merge and deploy.
If issues found, describe them and they'll be fixed on the same branch.
```

STOP here. The user reviews and then explicitly ships.

## Phase 4: Ship (only with `--ship`)

If `--ship` was passed, continue automatically after implementation:

1. Pull latest main: `git fetch origin {main}`
2. Rebase onto main: `git rebase origin/{main}`. If conflicts arise, STOP and report them. Do NOT auto-resolve.
3. Run Test command. ALL tests must pass after rebase. If any fail, STOP and report.
4. Run Build command. Must be clean.

Update ticket Regression Report section:
```markdown
## Regression Report
- Rebase onto {main}: clean (no conflicts)
- Tests after rebase: X passing, 0 failing
- Build after rebase: clean
- Tested at: {timestamp}
```

Merge to main:
1. `git checkout {main} && git pull origin {main}`
2. `git merge ticket/{branch-name} --no-ff -m "Merge {TKT-ID}: {title}"`
3. Run tests on main. If ANY test fails: `git reset --hard HEAD~1` and report. Do NOT push broken code.
4. Run build on main. Same: reset and report on failure.

Push and deploy:
- `git push origin {main}`
- If Deploy command is configured, run it.

Cleanup:
- `git branch -d ticket/{branch-name}`
- Update ticket status to `shipped`, update date.
- Move ticket with `git mv {tickets-dir}/{ID}.md {tickets-dir}/shipped/{ID}.md`
- Move any sibling brief files to `shipped/` the same way.
- `git commit -m "{TKT-ID}: archive shipped ticket"`
- `git push origin {main}`

Output:
```
{ID} SHIPPED

Merged to {main}: {merge commit hash}
Deployed: {timestamp or "skipped — no deploy configured"}
Branch cleaned up: yes

Summary: {1-2 sentence description of what shipped}
```

## If failure or major architecture drift occurs

If tests fail after rebase, the implementation plan proves unworkable, or major architecture drift is detected mid-implementation:
1. Stop immediately. Do NOT push broken code.
2. Set ticket status back to `open` (if investigation is now invalid) or `proposed` (if investigation is still sound but implementation needs revision).
3. Report what happened and why.
4. Instruct: "Re-run `/ticket-investigate {ID}` to refresh the plan before continuing."

## Rules

- Default is review, not ship. Only bypass the review checklist when `--ship` is explicitly passed.
- NEVER force push to main.
- NEVER push if tests or build fail after merge.
- High regression risk is a hard gate — do not auto-implement.
- The merge commit message must reference the ticket ID.
- If something goes wrong during merge/deploy, reset to a safe state and report.

## Compatibility Notes

- **Multi-ticket parallel execution → single-ticket only:** source `/ticket-chain` supports multi-ticket fan-out with parallel subagents, dependency graphs, wave execution, and rollup preview. This Copilot prompt targets single-ticket orchestration by default. For multi-ticket workflows, run this command once per ticket in the recommended order from `/ticket-investigate`.
- **Parallel subagents → inline sequential steps:** source uses the Agent tool for parallel investigation and implementation subagents. All phases are inlined sequentially here.
- **Wave execution → not applicable:** single-ticket mode has no waves. If a ticket's investigation reveals dependencies on other tickets, those must be shipped first (manually) before running this command.
- **Prowl notification:** source sends a Prowl push notification on completion. Prowl is not available in Copilot agent mode; add `--prowl` to the parent session if you need a push notification.
- **Rollup preview and CHAIN-REVIEW checklist:** source generates a consolidated multi-ticket review file and deploys to preview/staging. Single-ticket mode generates an inline checklist instead. For the full chain review format, use Claude Code's `/ticket-chain`.
