---
applyTo: "**"
---

# Brainstorm Mode

Read this before entering a brainstorm session (slash command `/brainstorm` or equivalent). Applies to any agent. Companion to `plan-mode.md` — they govern different phases and must not be confused.

## What brainstorm mode is for

Exploring a problem space with the user. The goal is to **produce a batch of scoped ticket stubs**, not a plan, not code. Long conversations are welcomed. Tangents are welcomed. External AI feedback is welcomed.

The failure mode this file prevents: "conversation produces a single giant ticket instead of N small ones."

## What brainstorm mode is NOT for

- Producing an implementation plan (that's `plan-mode.md`)
- Writing code (never, not even examples)
- Committing to a specific approach within a ticket

## Core rules

### Default to capture, not convergence
Every new topic the user raises is a candidate ticket unless they say otherwise. Don't try to unify tangents into a single coherent design — that's ticket-planning's job. Brainstorm's job is to *separate* concerns, not merge them.

### Maintain a running candidate-ticket list
Throughout the session, maintain an inline list of candidate tickets. Show it when the user asks "where are we?" or every ~10 exchanges. Format:

```
Candidate tickets so far:
1. {title} — {one-line scope}
2. {title} — {one-line scope}
...
```

### External feedback is a first-class input here
Gemini/Codex/other-agent pastes are welcome. For each piece, ask: "does this create a new candidate ticket, modify an existing one, or belong in a follow-up epic?" Don't just absorb.

### Code is forbidden
No snippets, no pseudocode, no type definitions. If an idea requires code to explain, it belongs in the downstream ticket's plan, not here. The furthest you go is filenames and one-sentence descriptions.

### Planning-level detail is forbidden
No step-by-step breakdowns. No "first we do X, then Y." If you find yourself producing those, you've slipped into plan mode — stop, and note the detail as "to be planned when ticket is scoped."

### Agent proposes splits; user approves
When the agent sees a candidate ticket growing too big, it proposes a split: *"TKT-X is getting wide — split into TKT-Xa (the core) and TKT-Xb (the policy layer)?"* User decides. Default is always: split.

### Stop condition — when the user signals they're done
The session ends when the user signals they're done: "produce the tickets," "ship it," "let's turn these into stubs," or similar. Don't guess at completion; wait for the signal. Not before, not after.

## Output format

On stop, produce two kinds of files under `{tickets-dir}/stub/` (the project's tickets directory, plus a `stub/` subdirectory parallel to `shipped/`, `deferred/`, `wontfix/`):

### 1. One epic file per brainstorm

`{tickets-dir}/stub/EPIC-<slug>.md`:

```yaml
---
id: EPIC-<slug>
title: "..."
status: stub
created: YYYY-MM-DD
---
```

```markdown
## North star
One paragraph: what are we actually trying to accomplish at this level.

## Out of scope
What this epic is NOT about.

## Tickets
- TKT-NNN: {title}
- TKT-NNN: {title}
```

### 2. One ticket stub per candidate

`{tickets-dir}/stub/TKT-NNN.md`:

```yaml
---
id: TKT-NNN
title: "..."
type: feature | bug | chore
status: stub
epic: EPIC-<slug>
depends_on: [TKT-MMM, ...]
created: YYYY-MM-DD
---
```

```markdown
## Summary
One paragraph: what and why.

## Acceptance criteria
- [ ] Specific, testable.
- [ ] ...

## Notes
Anything from the brainstorm specific to this ticket. Not a plan.
```

## ID assignment

When writing stubs at session-end, determine the next available IDs by scanning **all** ticket locations — the active `{tickets-dir}/*.md`, plus `stub/`, `shipped/`, `deferred/`, and `wontfix/` subdirs. Pick the next N sequential IDs. Write all N files in one pass before any downstream commits land.

## Sizing ticket stubs

Each stub must be **independently shippable or deferrable**. If TKT-A can't ship without TKT-B also shipping, either merge them or declare `depends_on: [TKT-B]` explicitly. No implicit coupling.

Each stub's acceptance criteria must be **testable by a human clicking something** — not "the code is well-architected." If you can't write a human-test for it, the scope is wrong.

## Epics are lightly integrated — by design

`EPIC-<slug>.md` files document the north star and member tickets. Only **two** commands know about epics:

- **`/ticket-investigate`** reads the epic's `## North star` section as read-only framing context when a ticket's frontmatter has an `epic:` field. It looks in the same directory as the ticket.
- **`/ticket-promote`** moves the epic alongside its tickets from `stub/` to the active set (and flips its status to `open`), so `/ti`'s same-directory lookup works after promotion.

Beyond those two, nothing integrates with epics:

- Epic files are not listed by `/tl`.
- "Epic shipped when all member tickets ship" is tracked manually by the human.
- `/ts`, `/ticket-status`, `/ticket-ship` etc. don't know about epics.

This is deliberate. A Plane migration is coming; Plane has native epic support (cycles/modules). Building richer epic-awareness into repo-based commands that are about to be replaced would be wasted work.

## Anti-patterns

- Producing a single giant ticket ("this is really all one thing").
- Writing implementation plans inside ticket stubs.
- Merging Gemini/Codex feedback into existing stubs instead of creating new ones.
- Producing code or pseudocode during brainstorm.
- Declaring "done" before the user signals completion.
- Silently dropping tangents the user raised. Capture them as stubs even if clearly out of scope — the user decides what to defer.

## Handoff

A brainstorm output is ready for **`/ticket-promote`** when:
- Epic file is written with a north star.
- N ticket stubs exist with frontmatter + acceptance criteria.

`/ticket-promote TKT-NNN [...]` moves stubs from `{tickets-dir}/stub/` into the active `{tickets-dir}/` and flips `status: stub → open`. That's the human gate between "someone brainstormed this" and "this is work we're committing to investigate."

Once promoted, `/ticket-investigate` (`/ti`) takes one or more ticket IDs. It reads the ticket stub + the parent epic's north star, then produces a plan per `plan-mode.md`.
