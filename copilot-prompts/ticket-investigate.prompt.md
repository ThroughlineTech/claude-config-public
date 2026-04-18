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

## Plan Mode Discipline

Before writing the plan, read `~/.claude/plan-mode.md` (and any project-local variant such as `docs/metaplanning/plan-mode.md`). The plan you produce must follow those rules:
- Fits on one screen (~60 lines) per ticket
- Includes a machine-readable `Relevant files` section
- Includes `investigated_at_sha: <SHA>` (the main-branch SHA you investigated against)
- Subtract-before-present pass: before finalizing, ask "what can be cut or deferred?"
- Split delight from fix: if the plan bundles a bug fix with a wow/delight feature, recommend splitting into separate tickets
- Flag file-size ceiling violations (e.g. Throughline's 300-line rule)
- Every plan names a human ship gate (not just automated tests)

When multiple tickets are planned in one session, the one-screen rule applies per ticket, not to the aggregate.

## Pre-flight Checks

- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- Ticket status MUST be `stub` or `open` (pre-investigation states). If already `proposed` or later, report the current status and stop — the ticket has already been investigated.
- Read the ticket's Description and Acceptance Criteria carefully.

## Single-Ticket Investigation

### Investigation Phase

1. **Understand the project context:**
   - Read `CLAUDE.md` (if it exists) for project rules.
   - Read `.claude/ticket-config.md` for stack info, key source locations, and context docs.
   - Read each "Context docs" path listed in the config.
   - **If the ticket's frontmatter has an `epic:` field**, read the parent epic for framing:
     - Locate the epic file in the **same directory as the ticket**, named `EPIC-<slug>.md`. The directory may be the active `{tickets-dir}/`, a stub/proposed subdir, or wherever the ticket happens to live.
     - Read **only** its `## North star` section. Treat it as read-only framing context — it tells you the parent objective so you can scope this one ticket correctly within it.
     - Do NOT read sibling tickets in the epic. Do NOT read a brainstorm transcript even if one exists next to the epic file. Do NOT expand `/ti`'s scope to cover the whole epic. This firewall is deliberate — it prevents the "one ticket balloons into the whole epic's worth of work" failure mode.
     - If the `epic:` field is present but the epic file is missing, emit a warning and proceed — treat the ticket as standalone.
   - If there's no `epic:` field, behave as usual (no epic context).

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

6. **Record the `investigated_at_sha`:**
   - Run `git rev-parse HEAD` if you're on `main`, or `git rev-parse origin/main` if you're on a branch.
   - Capture the resulting SHA — it goes in the plan footer.
   - Load-bearing for downstream drift detection and conflict scheduling.

### Proposal Phase

Write into the ticket file:

**Investigation section:**
- **If an epic was read:** lead with `Epic context: EPIC-<slug> — {one-line paraphrase of the north star}` so the user can verify the framing loaded correctly.
- What you found, with specific file paths and line numbers
- Root cause (for bugs) or architectural fit (for features)
- Regression risk assessment

**Proposed Solution section:**
- Clear description of the approach
- Why this approach over alternatives (if applicable)
- Any tradeoffs

**Implementation Plan section:**

Use the plan format from `plan-mode.md` (the `## Plan: {title}` heading from that doc is dropped here because the ticket section already names the plan):

```
{One paragraph: what, why, approach.}

**Relevant files**
- path/to/file.ts — what changes

**Steps**
1. …

**Verification**
- Specific checks, including at least one manual step if UI work.

**Out of scope**
- Explicit deferrals.

---
investigated_at_sha: <SHA>
```

`Relevant files` and `investigated_at_sha` are load-bearing (used by downstream drift detection and conflict scheduling) — not optional. Keep the whole plan block under ~60 lines.

### Subtract Before Presenting

Before moving to Finish, review your own draft plan and answer inline in the ticket:

- **What can be cut?** Items that aren't needed to meet the ticket's Acceptance Criteria.
- **What can be deferred to a follow-up ticket?** Adjacent improvements, not core requirements.
- **Does the plan fit on one screen (~60 lines)?** If not, cut or split.
- **Does any `Relevant file` already exceed the project's size ceiling** (e.g. Throughline's 300-line rule)? If your plan grows it further, propose a factor-first step.
- **Is this bundling a delight feature with a bug fix?** If yes, recommend splitting into separate tickets.

Document the answer (or a one-liner "nothing to cut — plan is minimal") inline in the ticket before updating status to `proposed`.

### Finish (single-ticket)

1. Update ticket status to `proposed`.
2. Update the `updated` date.
3. Output a summary:
   ```
   {ID} Investigation Complete

   Root Cause / Approach: {1-2 sentence summary}
   Plan: one screen (~{N} lines); Relevant files listed; investigated_at_sha: {SHA}
   Regression Risk: low | medium | high
   Implementation Steps: {count}
   Human ship gate: {named verification step}

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

Obey the same status check per ticket: must be `stub` or `open`. If a ticket is already `proposed`, print a notice ("TKT-XXX is already proposed — skipping re-investigation, reading existing plan") and read its existing Investigation + Implementation Plan instead.

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
Or:   /tch TKT-005 --ship, then /tch TKT-001 --ship, then /tch TKT-002 --ship   (one at a time in order)
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
