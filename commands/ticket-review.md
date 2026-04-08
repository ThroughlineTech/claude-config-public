---
description: 'TKT-XXX — generate a human verification checklist'
argument-hint: 'TKT-XXX'
---

# Review a Ticket

You are presenting a completed ticket implementation for human review. Generate a verification checklist that the user can follow to confirm the work is done correctly.

## Input
The argument is a ticket ID (e.g., TKT-001).

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
```

## Phase 2: Run Pre-merge Checks

1. Run the Test command from `.claude/ticket-config.md` (skip if not configured)
2. Run the Build command from `.claude/ticket-config.md` (skip if not configured)
3. Show a diff summary: `git diff {main-branch} --stat`

## Phase 3: Update Ticket

1. Write the Verification Checklist into the ticket file
2. Present it to the user in the conversation

## Finish

Output:
```
{ID} Ready for Review

Branch: {branch}
Changes: {diff stat summary}

## Verification Checklist
{the checklist}

Tests: {passing/skipped}
Build: {clean/skipped}

When verified, run /ticket-ship {ID} to merge and deploy
If issues found, describe them and I'll fix on the same branch.
```

## Rules
- Do NOT make code changes during review. This is read-only.
- If tests or build fail, set status back to `in-progress` and report the failures.
- The verification checklist must cover EVERY acceptance criterion from the ticket.
- Include regression checks for any area of the app that was touched.
