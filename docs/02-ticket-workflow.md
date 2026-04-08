# The Ticket Workflow

The ticket system is the core daily workflow in this repo. It's a lightweight in-repo issue tracker where each ticket is a markdown file, agents do the work, and the ticket file captures the full history of what was decided and why.

## Why tickets instead of issues/Linear/Jira

Four reasons:

1. **Co-located with code.** The ticket lives in the same git history as the change, so when you `git blame` a line six months later, you can trace it to the ticket that motivated it.
2. **Agent-readable.** Claude Code and Copilot can read and write the ticket directly. No API, no plugin, no "please paste the ticket details into chat."
3. **Cold-start resilient.** If you come back to a project after a month, `/ticket-list` tells you exactly what's in flight without requiring any context from you.
4. **Cross-machine.** Tickets live in the project's own git repo, so they're synced wherever you `git pull`.

## Ticket lifecycle

Every ticket moves through these statuses (defined in `tickets/TEMPLATE.md`):

```
open → proposed → [delegated] → in-progress → review → shipped
         ↓
       closed (abandoned)
```

- **open** — created but not yet investigated
- **proposed** — investigation complete, plan written, awaiting approval
- **delegated** — work has been handed off to another agent (via `/ticket-delegate`); brief file exists
- **in-progress** — approved and being implemented by Claude Code
- **review** — implementation complete, awaiting human verification
- **shipped** — merged to main (and deployed, if applicable)
- **closed** — abandoned without shipping

## The canonical lifecycle (Claude Code does everything)

This is the simplest path: Claude Code does every phase.

```bash
# 1. Create
/ticket-new "Redesign the project picker dropdown"

# 2. Investigate — Claude Code explores the codebase, writes a plan into the ticket
/ticket-investigate TKT-005
# Status: open → proposed
# Ticket now has: Investigation, Proposed Solution, Implementation Plan sections filled in

# 3. (You review the plan in tickets/TKT-005.md and decide if it's good)

# 4. Approve + implement — Claude Code creates a branch and does the work
/ticket-approve TKT-005
# Status: proposed → in-progress → review
# Feature branch ticket/tkt-005-redesign-project-picker-dropdown is created
# Implementation Plan items are checked off as they're done
# Files Changed, Test Report sections filled in

# 5. Review — Claude Code generates a human verification checklist
/ticket-review TKT-005
# Status stays at review
# Verification Checklist (for human) section filled in

# 6. (You manually verify using the checklist. On a device, in a browser, whatever.)

# 7. Ship — Claude Code rebases onto main, runs tests, merges, optionally deploys
/ticket-ship TKT-005
# Status: review → shipped
# Branch deleted
```

## The cross-model lifecycle (delegate to Gemini)

Same workflow, but the implementation is done by a different model via Copilot Chat:

```bash
# 1-3. Same as above
/ticket-new "..."
/ticket-investigate TKT-005
# (you review)

# 4. Delegate the implementation — Claude Code writes a brief file
/ticket-delegate TKT-005 implement
# Status: proposed → delegated
# Branch ticket/tkt-005-... is created
# Brief written to: tickets/TKT-005.implement.brief.md

# 5. Switch to VS Code Copilot Chat, pick a model (e.g. Gemini)
# Run in Copilot Chat: /run-brief tickets/TKT-005.implement.brief.md
# Gemini reads the brief, implements the plan, commits, pushes
# When Gemini reports "Brief executed", you come back to Claude Code

# 6. Collect the work — Claude Code reads the diff, updates the ticket
/ticket-collect TKT-005
# Status: delegated → review
# Files Changed, Test Report sections filled in (based on the diff + commit messages)

# 7-8. Review and ship as before
/ticket-review TKT-005
# (you verify)
/ticket-ship TKT-005
```

## The paranoid lifecycle (with peer review)

For tickets where you want a second opinion from a different model before committing to a direction:

```bash
/ticket-new "..."
/ticket-investigate TKT-005                  # Claude Code investigates
/ticket-delegate TKT-005 verify investigate   # Write a peer-review brief
# Status: proposed → delegated (target: investigate)

# Open Copilot Chat with a DIFFERENT model (e.g. Gemini)
# Run: /run-brief tickets/TKT-005.verify-investigate.brief.md
# Gemini reads the ticket's Investigation/Proposed Solution/Implementation Plan
# Gemini writes a "## Peer Review (verify-investigate)" section into the ticket

/ticket-collect TKT-005
# Status: delegated → proposed (returns to proposed so you can revise if needed)

# Read the ticket file. See what Gemini flagged.
# If the peer review raised valid concerns:
#   - Re-run /ticket-investigate TKT-005 (it will revise, taking the peer review into account)
#   - Or manually edit the Implementation Plan based on Gemini's feedback
# If the peer review agreed, proceed:
/ticket-approve TKT-005
```

Same pattern works for `verify implement` (peer-review the diff before shipping) and `verify review` (peer-review the human verification checklist before you start clicking through it).

## Ticket file anatomy

Each ticket is a markdown file at `{tickets-dir}/TKT-NNN.md` (where `{tickets-dir}` is configured in the project's `.claude/ticket-config.md`). The file has two distinct zones:

### Zone 1 — Human-written (you fill in)

```yaml
---
id: TKT-005
title: "Redesign the project picker dropdown"
type: enhancement
status: open
priority: medium
branch: ""
created: 2026-04-07
updated: 2026-04-07
---

## Description
{what needs to happen, in your own words}

## Reproduction Steps (bugs only)
{step by step for bugs}

## Acceptance Criteria
- [ ] {observable, specific criteria}
```

### Zone 2 — Agent-filled (don't edit manually)

```markdown
## Investigation
{filled in by /ticket-investigate}

## Proposed Solution
{filled in by /ticket-investigate}

## Implementation Plan
- [ ] {filled in by /ticket-investigate}

## Files Changed
{filled in by /ticket-approve or /ticket-collect}

## Test Report
{filled in by /ticket-approve or /ticket-collect}

## Verification Checklist (for human)
- [ ] {filled in by /ticket-review}

## Regression Report
{filled in by /ticket-ship}

## Delegation Log
{filled in by /ticket-delegate and /ticket-collect — audit trail of delegated phases}

## Peer Review (verify-investigate)
## Peer Review (verify-implement)
## Peer Review (verify-review)
{filled in by the peer-reviewing agent via /ticket-delegate ... verify ...}
```

The split matters: you write the **what** (description, acceptance criteria, priority), agents write the **how** (investigation, plan, implementation, tests, review). The ticket file is the durable contract between you and the agents.

## Bootstrapping a project for tickets

Before you can use `/ticket-new` in a project, the project needs a `tickets/` directory and a `.claude/ticket-config.md`. Run this once in each project:

```bash
# In any Claude Code session inside the project
/ticket-install
```

`/ticket-install` detects the stack (Node/Swift/Rust/Go/Python/etc.), proposes test/build/deploy commands, asks you to confirm, and writes:

- `tickets/TEMPLATE.md` — the template every new ticket is copied from
- `.claude/ticket-config.md` — project-specific config (stack, tickets dir, commands, key source paths, context docs)
- Appends a `## Tickets` section to the project's `CLAUDE.md`

See [06-adding-a-new-machine.md](06-adding-a-new-machine.md) for a concrete example of `/ticket-install` on a Swift project.

## Where the ticket files live

- **`tickets/`** directory at the project root (configurable via `.claude/ticket-config.md`)
- **Not** in the `claude-config` repo — tickets are project-specific and live in each project's own git history
- **Brief files** (`tickets/TKT-XXX.{phase}.brief.md`) also live in the project's `tickets/` directory, alongside the ticket files
- The `claude-config` repo only provides the **commands** and **brief templates**; the actual ticket files stay with the project

## Common operations

### "What's in flight across all my tickets in this project?"

```bash
/ticket-list
```

### "What's the status of this specific ticket? What do I do next?"

```bash
/ticket-status TKT-005
```

Returns a lifecycle timeline with attribution (which phases were done by which agent, when, and what the next action is).

### "I want to retry the investigation — Claude Code's first pass missed something"

Manually edit the ticket to remove the Investigation section, change status back to `open`, then re-run:

```bash
/ticket-investigate TKT-005
```

(Future improvement: a `--revise` flag that does this cleanly. For now, manual.)

### "The brief file is wrong somehow — can I delete it?"

Yes, but do it carefully:

1. Make sure the ticket status is back to a pre-delegation state (edit the frontmatter manually if needed)
2. Delete the specific `.brief.md` file
3. Re-run `/ticket-delegate` with the right arguments

Brief files are not sacred — they're generated artifacts. Delete and regenerate as needed.

### "I want to work on this ticket myself without using `/ticket-approve`"

Fine. Check out the branch manually, edit code, commit, push. Just remember to:

1. Update the ticket's `status` field manually as you progress
2. Fill in Files Changed, Test Report sections when done
3. Then run `/ticket-review` and `/ticket-ship` as usual

The ticket commands are conveniences, not requirements. The file is the source of truth.

## Don't do these

- **Don't delete or rewrite agent-filled sections** unless you're intentionally reverting a phase. Those sections are how future-you (or another agent) reconstructs what happened.
- **Don't commit to main directly** while a ticket is in progress. The `/ticket-approve` and `/ticket-ship` flow assumes you're on a feature branch.
- **Don't skip `/ticket-review`.** Even if you're sure the implementation is right, the verification checklist is useful for human sanity-checking and for the ticket's audit trail.
- **Don't forget to run `/ticket-install` in a project before trying `/ticket-new`.** The universal commands require `.claude/ticket-config.md` to exist; they'll tell you to bootstrap if it's missing.
