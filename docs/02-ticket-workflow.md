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
open → proposed → [delegated] → in-progress → review → shipped  (→ shipped/)
  ↓                                                ↓
  └──────────────→  deferred (→ deferred/)    wontfix (→ wontfix/)
```

**Active statuses** (ticket file lives at `tickets/{ID}.md`):
- **open** — created but not yet investigated
- **proposed** — investigation complete, plan written, awaiting approval
- **delegated** — work has been handed off to another agent (via `/ticket-delegate`); brief file exists
- **in-progress** — approved and being implemented
- **review** — implementation complete, awaiting human verification

**Terminal statuses** (ticket file is moved into a subfolder, with `git mv`, so the active set stays clean):
- **shipped** → `tickets/shipped/{ID}.md` — merged to main (and deployed, if applicable). Set by `/ticket-ship`.
- **deferred** → `tickets/deferred/{ID}.md` — investigated or considered, not doing it right now, may revisit. Set by `/ticket-defer {ID} {reason}`.
- **wontfix** → `tickets/wontfix/{ID}.md` — closed without shipping: duplicate, invalid, obsolete, superseded. Set by `/ticket-close {ID} {reason}`.

Terminal tickets can be brought back to active with `/ticket-reopen {ID}` — useful when a shipped change regresses, a deferred ticket's moment arrives, or a closed one turns out to be real after all. The terminal subfolders are **created lazily** on first use (no `.gitkeep` — the first `git mv` populates them).

## Preview vs. ship

These are two different operations and mixing them up will hurt you:

- **Preview** = build the ticket's feature branch and make it inspectable without touching main. Localhost, staging URL, iOS simulator, whatever the project's `Preview command` is configured to do. `/ticket-preview {ID}` runs the preview for one ticket; `/ticket-batch` runs previews for many.
- **Ship** = merge to main, (optionally) deploy to prod, archive the ticket into `tickets/shipped/`. This is the production action. Always an explicit per-ticket decision.

You smoke-test in **preview**. You ship what passes. Never ship to smoke-test.

### Preview profiles

Real projects aren't one-shape-fits-all. A repo can have a macOS host and an iOS companion, or a client and a server that must both run for any test to be meaningful. So `.claude/ticket-config.md` defines **preview profiles** — named recipes — and each ticket picks one via its `app:` field.

Profiles come in two flavors:

- **Atomic profile** — one command that launches one thing. Has a Command, a Port offset, a Ready-when rule (`http {path}` / `log {pattern}` / `delay {seconds}` / `command-exit`), a Sequential flag (true for things like iOS simulator that can't coexist), and an optional Depends-on list.
- **Compound profile** — an ordered list of atomic profiles to launch together. The canonical use cases: `fullstack: [server, client]` where the client needs a running server, and `pair: [macos, ios]` where an iOS companion app needs its macOS host running (Bonjour pairing, cross-device features, etc.).

**Port computation** is deterministic per (ticket, component): `{Preview port base} + {numeric-id} + {component's port offset}`. The first component has offset 0, each subsequent atomic profile defaults to offset +1000. So TKT-014's `fullstack` preview is server on `3014` and client on `4014`. Same ticket always gets the same ports — no collisions between parallel previews.

**Placeholders** inside a profile's Command:
- `{PORT}` — this component's computed port
- `{ID}`, `{BRANCH}`, `{WORKTREE}` — ticket-level substitutions
- `{<OTHER_COMPONENT>_PORT}` — another component's port in the same compound (e.g. `{SERVER_PORT}` inside the client command), substituted after all ports are computed

Each ticket's frontmatter has an `app:` field naming the profile it uses. `/ticket-new` asks at creation time (via AskUserQuestion) if the project has 2+ profiles; otherwise it picks silently. `/ticket-preview` reads `app:`, looks up the profile, launches all its components in dependency order, waits for each component's readiness signal, and records a multi-line `.preview.pid` file so teardown can kill everything cleanly.

`Preview mode` stays project-wide: `auto` (rollup if possible, fall back to individual on merge conflict), `rollup` (combine or fail), `individual` (one preview per ticket). `auto` automatically degrades to `individual` if any profile in the project has a `Sequential: true` component (iOS simulator, anything else that's a system singleton).

**Batch grouping.** `/ticket-batch` groups tickets by their `app:` profile and handles each group independently: server-only tickets can rollup + run parallel, iOS tickets run sequentially, fullstack tickets run at their own port pair per ticket. One final prowl, grouped preview summary.

## Batch workflow

`/ticket-batch` is the "queue up a bunch of work and come back later" command. It:

1. Auto-reaps any stale worktrees from previous batches.
2. Takes a list of ticket IDs (or all `open` tickets with no argument).
3. Creates a **git worktree** per ticket under `.worktrees/ticket-{id}/`. Parallel worktrees mean no branch-switching contention and each subagent gets fresh context.
4. Does a pre-implement conflict check (advisory, based on Implementation Plans) and warns about overlaps.
5. Spawns one subagent per ticket, **in parallel**, to run investigate → auto-approve → implement. Each subagent works entirely inside its own worktree.
6. **High regression risk is a manual gate** — if a ticket's investigation writes `Regression Risk: high`, the batch pauses it at `proposed` and calls it out in the final report. Everything else auto-implements.
7. Does a post-implement conflict check (authoritative, based on `git diff` file sets) and attaches "also modified by TKT-XXX" notes to the preview output.
8. Runs the preview in whichever mode the project is configured for.
9. **Sends one prowl** when the whole batch is ready. Never per-ticket.

You then come back, poke at the previews, and decide each ticket's fate with `/ticket-ship`, `/ticket-defer`, or `/ticket-close`.

### The auto-cleanup contract

You never manage worktrees or preview processes by hand. The system cleans up through three layers:

1. **Side-effects on terminal transitions.** `/ticket-ship`, `/ticket-defer`, `/ticket-close` all kill the ticket's preview process and remove its worktree as a final step. If a rollup preview is live when you defer or close a ticket, the rollup is **rebuilt** excluding that ticket (or killed if no `review` tickets remain).
2. **Explicit reaper.** `/ticket-cleanup` is the manual form: `/ticket-cleanup {ID}` for one ticket, `/ticket-cleanup --all` for everything, or `/ticket-cleanup` with no arg to reap only stale worktrees (tickets in terminal folders or missing).
3. **Ambient auto-reap.** `/ticket-list`, `/ticket-status`, and `/ticket-batch` all run the no-arg reaper as a silent preflight step. You never have to remember to clean up — it happens because you were already going to look at tickets.

Together these guarantee: a shipped ticket never leaves a worktree behind, a crashed batch self-heals the next time you run any ticket command, and `.worktrees/` only ever contains in-flight work.

`.worktrees/` should be in `.gitignore`.

### Why subfolders

ID allocation is derived from the highest existing ticket number. `/ticket-new` scans `tickets/**/{PREFIX}*.md` **recursively** — including the terminal subfolders — so a shipped or closed ticket can never have its ID reused. This is a load-bearing invariant: if you add new terminal states later, they MUST be scanned by `/ticket-new` too, or numbering will collide.

### Reasons are stored in English

`/ticket-defer` and `/ticket-close` require a reason. You can type the reason in any language (e.g. Danish); the command translates it to clear English before writing it into the ticket. Only the English form is stored — there's no value in keeping both.

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

Hand the entire ticket to a different model. It investigates and implements with its own perspective; Claude reviews the result.

```bash
/ticket-new "..."

# Delegate the full lifecycle — Claude writes a brief, creates the branch
/ticket-delegate TKT-005
# Status: open → delegated
# Branch ticket/tkt-005-... is created
# Brief written to: tickets/TKT-005.full.brief.md

# Switch to VS Code Copilot Chat, pick a model (e.g. Gemini)
# Run in Copilot Chat: /run-brief tickets/TKT-005.full.brief.md
# Gemini investigates, implements, tests, commits, pushes
# When Gemini reports "Brief executed", come back to Claude Code

# Collect — Claude reviews the investigation + diff + tests
/ticket-collect TKT-005
# Status: delegated → review (if approved)
# Claude writes a Delegation Review with verdict + any issues

# Ship as before
/ticket-ship TKT-005
```

You can also delegate individual phases if you want Claude to handle some and another model to handle others (e.g., `/ticket-delegate TKT-005 implement` for implementation only). See [03-delegation.md](03-delegation.md).

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

## Automated Checks
{filled in by /ticket-review or /ticket-chain — pass/fail results from tests, build, lint, typecheck, rebase status}

## Verification Checklist (for human)
- [ ] {filled in by /ticket-review — manual-only steps}

## Regression Report
{filled in by /ticket-ship}

## Delegation Log
{filled in by /ticket-delegate and /ticket-collect — audit trail of delegated phases}

## Delegation Review
{filled in by /ticket-collect for full-lifecycle delegations — Claude's code review of the other model's work}

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

`/ticket-install` detects the stack (Node/Swift/Rust/Go/Python/etc.), proposes test/build/deploy commands, verifies the default branch is `main` (warns and offers to rename if it's `master`), asks you to confirm, and writes:

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
