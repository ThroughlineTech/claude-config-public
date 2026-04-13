---
description: 'TKT-XXX — generate a human verification checklist'
argument-hint: 'TKT-XXX'
---

# Review a Ticket

You are presenting a completed ticket implementation for human review. Generate a verification checklist that the user can follow to confirm the work is done correctly.

## Input
The argument is a ticket ID (e.g., TKT-001).

**ID shorthand:** If the argument is a bare number (e.g., `26` or `3`), resolve it to a full ticket ID: read the ticket prefix from `.claude/ticket-config.md`, scan existing ticket files to determine the zero-padding width, and expand (e.g., `26` → `TKT-026`).

**Locate the ticket file:** at `{tickets-dir}/{ID}.md`. If the ticket is in a terminal subfolder (`shipped/`, `deferred/`, `wontfix/`), STOP and tell the user to run `/ticket-reopen {ID}` first.

## Pre-flight Checks
- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- Read Test and Build commands from `.claude/ticket-config.md`.
- Ticket status MUST be `review`. If not, report the current status and stop.
- Verify the feature branch exists and is checked out.

## Phase 1: Generate Verification Checklist

Based on the ticket's Acceptance Criteria, Implementation Plan, and actual changes made, create a **human-testable** verification checklist. Each item must be:

- **Specific**: "Navigate to /projects/123 and click 'Start'" not "Test the feature"
- **Observable**: Describe what the user should SEE, not what the code does
- **Independent**: Each item can be verified on its own
- **Ordered**: Steps should flow naturally

### Structure the checklist as

```markdown
## Verification Checklist (for human)

### Setup
- [ ] Build/run the project locally (use the project's standard run command)
- [ ] Ensure you are in the right state (logged in, on the right screen, etc.)

### Core Functionality
- [ ] Step 1: Do X, expect to see Y
- [ ] Step 2: Do X, expect to see Y

### Edge Cases
- [ ] Step N: Try X with invalid input, expect error message Y

### Regression Checks
- [ ] Existing feature A still works: do X, see Y
- [ ] Existing feature B still works: do X, see Y

### Verdict
- [ ] pass
- [ ] fail — reason:
```

## Phase 2: Automated verification

Run every check that can be verified without a human. Read Test, Build, and Lint commands from `.claude/ticket-config.md`. Determine the main branch: read `Main branch` from `.claude/ticket-config.md` if present, otherwise fall back to `git symbolic-ref refs/remotes/origin/HEAD`. If the result is `master`, warn the user and suggest running `/ticket-install` to migrate.

On the ticket's feature branch:

1. **Tests**: run the Test command. Capture pass/fail + counts (passed, failed, skipped).
2. **Typecheck**: run typecheck if configured (often part of Test or Lint). Capture pass/fail.
3. **Build**: run the Build command. Capture pass/fail + first error if any.
4. **Lint**: run the Lint command if configured. Capture pass/fail + warning count.
5. **Branch rebased on main**: `git merge-base --is-ancestor origin/{main} HEAD`. Pass if yes.
6. **No merge conflicts**: verify clean merge with main. Pass if clean.
7. Show a diff summary: `git diff {main-branch} --stat`

Omit any check whose command is not configured — don't report "skipped."

## Phase 3: Update Ticket

1. Write the `### Automated Checks` section into the ticket's `## Verification Checklist (for human)` area, using this format:

```markdown
### Automated Checks
- [x] Tests: 47 passed, 0 failed, 2 skipped
- [x] Typecheck: clean
- [x] Build: clean
- [x] Lint: clean (3 warnings)
- [x] Branch rebased on main: yes
- [ ] ~~Tests: 3 failed~~ (`src/auth.test.ts:42 — expected 200, got 500`)

> All automated checks passed.
```

Format rules:
- `[x]` for passing, `[ ] ~~strikethrough~~` for failing with first error detail
- Omit lines for unconfigured commands
- End with `> All automated checks passed.` or `> {N} automated check(s) failed — review before shipping.`

2. Write the human verification checklist (from Phase 1) below the automated checks
3. Present it to the user in the conversation

## Finish

Output:
```
{ID} Ready for Review

Branch: {branch}
Changes: {diff stat summary}

## Automated Checks
{automated check results — pass/fail per check}

## Verification Checklist (manual)
{the human checklist}

When verified, run /ticket-ship {ID} to merge and deploy
If issues found, describe them and I'll fix on the same branch.
```

## Rules
- Do NOT make code changes during review. This is read-only.
- If tests or build fail, set status back to `in-progress` and report the failures.
- The verification checklist must cover EVERY acceptance criterion from the ticket.
- Include regression checks for any area of the app that was touched.
