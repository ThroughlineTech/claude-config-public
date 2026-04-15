---
mode: agent
description: Investigate a ticket and write an implementation plan
argument-hint: 'TKT-XXX [TKT-YYY ...] [--order-only] [--in-given-order] [--auto]'
---

# Investigate a Ticket

You are an autonomous agent investigating one or more tickets. You will explore the codebase, understand the problem deeply, and propose a concrete solution for human approval.

## Input

**Parse flags first.** Any argument starting with `--` is a flag, not a ticket ID. Extract flags before processing IDs.

Recognized flags:
- `--in-given-order` — investigate in the given order; skip the post-investigation ordering recommendation.
- `--order-only` — for multi-ticket input: run ordering analysis only (no investigation pass); output recommended order with rationale and stop.
- `--auto` — for multi-ticket input: after investigating and ordering, automatically proceed in recommended order without pausing.

**Resolve IDs:** All remaining arguments are ticket IDs. If an argument is a bare number (e.g., `26` or `3`), resolve it to a full ticket ID: read the ticket prefix from `.claude/ticket-config.md`, scan existing ticket files to determine zero-padding width, and expand (e.g., `26` → `TKT-026`).

**Route by count:**
- 0 IDs → error: no ticket ID provided.
- 1 ID → **single-ticket path** (see below).
- 2+ IDs → **multi-ticket path** (see Multi-ticket mode below).

**Locate ticket files (single-ticket path):** check `{tickets-dir}/{ID}.md` first. If not found there, check terminal subfolders (`shipped/`, `deferred/`, `wontfix/`). If the ticket is in a terminal subfolder, STOP and tell the user to run `/ticket-reopen {ID}` first. If not found anywhere, error.

## Pre-flight Checks

- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- Ticket status MUST be `open`. If not, report the current status and stop.
- Read the ticket's Description and Acceptance Criteria carefully.

## Single-Ticket Investigation

### Investigation Phase

1. **Understand the project context:**
   - Read `CLAUDE.md` (if it exists) for project rules.
   - Read `.claude/ticket-config.md` for stack info, key source locations, and context docs.
   - Read each "Context docs" path listed in the config.

2. **Deep-dive the relevant code:**
   - Use "Key source locations" from the config as starting points.
   - Search the codebase for all files related to the ticket's domain.
   - Read every relevant file end-to-end. Do not skim.
   - Map the call chain end-to-end (entry point → business logic → data layer).
   - Identify all interfaces, types, and contracts involved.
   - Note existing test coverage for affected areas.

3. **For bugs:** reproduce the issue mentally by tracing the code path. Identify the root cause.

4. **For features:** identify where the new code fits in the architecture, what interfaces need extending, what new files are needed.

5. **Identify regression risks:**
   - What existing tests cover the affected code?
   - What user-facing flows touch this code?
   - What could break if this change is done wrong?

### Proposal Phase

Write into the ticket file:

**Investigation section:**
- What you found, with specific file paths and line numbers
- Root cause (for bugs) or architectural fit (for features)
- Regression risk assessment

**Proposed Solution section:**
- Clear description of the approach
- Why this approach over alternatives (if applicable)
- Any tradeoffs

**Implementation Plan section:**
- Numbered checklist of specific implementation steps
- Each step must reference specific files to create/modify
- Include steps for: interface changes, implementation, unit tests, integration tests
- Include a step for regression testing existing tests

### Finish (single-ticket)

1. Update ticket status to `proposed`.
2. Update the `updated` date.
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

## Multi-ticket Mode

Activated when 2+ ticket IDs are provided. Investigate all tickets sequentially in one agent session, then output a recommended implementation order.

### 1. Pre-flight

For every ID given:
- Locate the ticket file (same lookup as single-ticket path above).
- If a ticket is in a terminal subfolder, STOP and report which IDs are terminal; tell the user to reopen them first.
- If any ticket file is not found, STOP and report the missing IDs.

### 2. Sequential investigation loop

Investigate each ticket one at a time in the input/ID order. For each ticket, run the full single-ticket investigation (Pre-flight Checks + Investigation Phase + Proposal Phase + Finish as defined above).

Obey the same "MUST be open" status check per ticket. If a ticket is already `proposed`, print a notice ("TKT-XXX is already proposed — skipping re-investigation, reading existing plan") and read its existing Investigation + Implementation Plan instead.

After each ticket completes, print a one-line progress summary before starting the next:
```
✓ TKT-001 investigated (1/3) — risk: low, files: 4
```

If `--order-only` was passed, skip investigation entirely and proceed directly to step 3 using existing plan sections.

### 3. Post-investigation ordering analysis

After all tickets have been investigated (or skipped), analyze the completed Investigation and Implementation Plan sections and compute a recommended implementation order.

**Skip this step if `--in-given-order` was passed.**

**Scoring priority (apply in order; use next criterion only to break ties):**
1. **Declared dependencies** — if ticket A's Investigation or Implementation Plan states ticket B must go first, A comes after B. Build a dependency graph; tickets with no unresolved dependencies come first.
2. **Risk / blast radius** — tickets with `Regression Risk: high` or `medium` come before `low`.
3. **Shared-file conflicts** — if two tickets touch the same files, sequence the foundational change first.
4. **Quick-win value** — high value + low complexity breaks ties in favor of going first.
5. **Ticket ID** — deterministic tiebreaker (lower ID first).

**Output format:**
```
Investigations complete — {N} tickets

TKT-005  "{title}"  risk: low   → implement 1st: no dependencies, quick win
TKT-001  "{title}"  risk: med   → implement 2nd: unblocks TKT-002 (declared dep)
TKT-002  "{title}"  risk: low   → implement 3rd: depends on TKT-001; shares {shared-file}

Next: /ta TKT-005, then /ta TKT-001, then /ta TKT-002
Or:   /tch 5 1 2 --ship   to implement and ship all in this order
```

Each line includes: ticket ID, quoted title, risk level, position, and one-line rationale.

If `--auto` was passed, proceed to approve and implement in the recommended order automatically (inline the `/ticket-approve` steps for each ticket in sequence).

## Rules

- Do NOT make any code changes. Investigation only (unless `--auto` is active).
- Do NOT create branches. That happens on approval.
- Be thorough. A bad investigation leads to a bad implementation.
- Reference specific file paths and line numbers, not vague descriptions.
- If you discover the ticket is invalid or already fixed, update status to `closed` with explanation.

## Compatibility Notes

- **Multi-ticket parallel subagents → sequential loop:** source spawns parallel investigation subagents via the Agent tool. In Copilot agent mode this is adapted to a sequential loop in one session. The output and behavior are identical; only wall-clock time differs.
- **`--order-only`, `--in-given-order`, `--auto` flags:** added per command-specific policy override; not in original source but represent extensions for Copilot use.
