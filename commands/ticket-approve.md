# Approve and Implement a Ticket

You are an autonomous agent implementing an approved ticket. You will create a branch, implement the solution, write tests, verify no regressions, and present results for review.

## Input
The argument is a ticket ID (e.g., TKT-001).

**Locate the ticket file:** look at `{tickets-dir}/{ID}.md` first. If the ticket is in a terminal subfolder (`shipped/`, `deferred/`, `wontfix/`), STOP and tell the user to run `/ticket-reopen {ID}` first.

## Pre-flight Checks
- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- Read the Test, Build, and Lint commands from `.claude/ticket-config.md`.
- Ticket status MUST be `proposed`. If not, report status and stop.
- The Implementation Plan must be filled in. If empty, stop and tell the user to run `/ticket-investigate` first.
- Ensure working tree is clean (`git status`). If dirty, warn the user and stop.

## Phase 1: Branch Setup

1. Determine the main branch (usually `main`, sometimes `master` or `develop`). Check `git symbolic-ref refs/remotes/origin/HEAD` if unsure.
2. Ensure you're on main and it's up to date: `git checkout {main} && git pull`
3. Create a feature branch: `git checkout -b ticket/{lowercased-id}-{slugified-title}`
   - Example: `ticket/tkt-001-fix-auth-redirect`
4. Update the ticket: set `branch` field, status to `in-progress`, update date

## Phase 2: Implementation

Work through the Implementation Plan checklist item by item. For EACH step:

1. **Read before writing.** Read every file you're about to modify.
2. **Follow project rules from `CLAUDE.md`** (if it exists).
3. **Write clean code:**
   - Follow existing patterns in the codebase
   - Use existing interfaces and extend them properly
   - Handle errors at system boundaries
4. **Check off each plan item** in the ticket as you complete it

## Phase 3: Testing

1. **Add tests** for every new function/method following the project's existing test conventions:
   - Test happy path and error cases
   - Test edge cases relevant to the change

2. **Run tests** using the Test command from `.claude/ticket-config.md`:
   - Every test must pass. Fix failures immediately.
   - If a test you didn't write fails, that's a regression — fix it.
   - If no Test command is configured, skip and note it in the Test Report.

3. **Run build** using the Build command from `.claude/ticket-config.md`:
   - Must complete cleanly with zero errors
   - If no Build command is configured, skip and note it in the Test Report.

4. **Run lint** if a Lint command is configured.

## Phase 4: Document Results

Update the ticket file:

### Files Changed section
- List every file created or modified with a one-line description

### Test Report section
- Number of tests added
- Number of tests passing (total)
- Build status
- Any warnings

## Phase 5: Commit

1. Stage relevant files: `git add {specific files}` (NOT `-A`)
2. Commit with message: `{TKT-ID}: {title}`
3. If multiple logical units, use multiple commits with `{TKT-ID}: description`

## Finish

1. Update ticket status to `review`
2. Output summary:
   ```
   {ID} Implementation Complete

   Branch: {branch}
   Commits: {count}
   Files Changed: {count}
   Tests Added: {count}
   All Tests Passing: yes/no
   Build Clean: yes/no

   Next: run /ticket-review {ID} to see verification checklist
   ```

## Rules
- Work in the feature branch, NEVER commit to main directly
- If you discover the proposed solution won't work, update the ticket with findings and set status back to `open`. Do NOT ship broken code.
- If tests fail and you can't fix them within the scope of the ticket, stop and report.
- Every commit should be atomic and buildable.
