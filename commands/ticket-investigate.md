# Investigate a Ticket

You are an autonomous agent investigating a ticket. You will explore the codebase, understand the problem deeply, and propose a concrete solution for human approval.

## Input
The argument is a ticket ID (e.g., TKT-001).

**Locate the ticket file:** look first at `{tickets-dir}/{ID}.md` (active set). If not found there, check the terminal subfolders `{tickets-dir}/shipped/`, `{tickets-dir}/deferred/`, and `{tickets-dir}/wontfix/`. If the ticket lives in a terminal subfolder, STOP and tell the user to run `/ticket-reopen {ID}` first — terminal tickets are not eligible for investigation until reopened. If not found anywhere, error.

## Pre-flight Checks
- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- Ticket status MUST be `open`. If not, report the current status and stop.
- Read the ticket's Description and Acceptance Criteria carefully.

## Investigation Phase

1. **Understand the project context**:
   - Read `CLAUDE.md` (if it exists) for project rules
   - Read `.claude/ticket-config.md` for stack info, key source locations, and context docs
   - Read each "Context docs" path listed in `ticket-config.md`

2. **Deep-dive the relevant code**:
   - Use the "Key source locations" from `ticket-config.md` as your starting points
   - Search the codebase for all files related to the ticket's domain
   - Read every relevant file end-to-end. Do not skim.
   - Map out the call chain end-to-end (entry point → business logic → data layer)
   - Identify all interfaces, types, and contracts involved
   - Note existing test coverage for affected areas

3. **For bugs**: reproduce the issue mentally by tracing the code path. Identify the root cause.
4. **For features**: identify where the new code fits in the architecture, what interfaces need extending, what new files are needed.

5. **Identify regression risks**:
   - What existing tests cover the affected code?
   - What user-facing flows touch this code?
   - What could break if this change is done wrong?

## Proposal Phase

Write into the ticket file:

### Investigation section
- What you found, with specific file paths and line numbers
- Root cause (for bugs) or architectural fit (for features)
- Regression risk assessment

### Proposed Solution section
- Clear description of the approach
- Why this approach over alternatives (if applicable)
- Any tradeoffs

### Implementation Plan section
- Numbered checklist of specific implementation steps
- Each step should reference specific files to create/modify
- Include steps for: interface changes, implementation, unit tests, integration tests
- Include a step for regression testing existing tests

## Finish

1. Update ticket status to `proposed`
2. Update the `updated` date
3. Output a summary:
   ```
   {ID} Investigation Complete

   Root Cause / Approach: {1-2 sentence summary}
   Files Affected: {list}
   Regression Risk: low | medium | high
   Implementation Steps: {count}

   Review the proposal in {ticket path}
   Next: run /ticket-approve {ID} to approve and begin implementation
   ```

## Rules
- Do NOT make any code changes. Investigation only.
- Do NOT create branches. That happens on approval.
- Be thorough. A bad investigation leads to a bad implementation.
- Reference specific file paths and line numbers, not vague descriptions.
- If you discover the ticket is invalid or already fixed, update status to `closed` with explanation.
