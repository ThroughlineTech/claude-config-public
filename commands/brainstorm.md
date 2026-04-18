---
description: 'start a brainstorm session — produce scoped ticket stubs'
argument-hint: '[topic] [--prowl]'
---

# Brainstorm

Start a brainstorm session. The goal is to produce a batch of scoped ticket stubs — **not a plan, not code.**

## Read first

**Before starting the session, read `~/.claude/brainstorm-mode.md`.** The rules there are not optional: capture over convergence, no code, no implementation plans, user signals the end.

## Input

- Optional topic/title for the session (free text). Pass anything that helps frame the problem space.
- If no argument, ask the user "what do you want to brainstorm?" and proceed.
- `--prowl` — send a Prowl notification when stubs have been written.

## Pre-flight

- Read `.claude/ticket-config.md` if it exists. Capture the ticket prefix, zero-padding width, and tickets directory. If missing, tell the user to run `/ticket-install` and stop.
- Note the path `{tickets-dir}/stub/`. Create it if it doesn't exist (at session-end, not now).

## During the session

Follow the Core rules in `brainstorm-mode.md`:

1. **Default to capture, not convergence.** Every new topic is a candidate ticket.
2. **Maintain a running candidate-ticket list** inline. Show it when asked or every ~10 exchanges.
3. **Propose splits** when a candidate grows too wide. Default is split; user approves.
4. **Triage external feedback** (Gemini/Codex/other agent pastes): new ticket, modify existing, or follow-up epic?
5. **No code.** No step-by-step plans. Filenames + one-sentence descriptions max.
6. **Do not declare the session done.** Wait for the user's signal ("produce the tickets," "ship it," "let's turn these into stubs," or similar).

## On stop signal

When the user signals they're ready for output:

1. **Compute next IDs.** Scan `{tickets-dir}/*.md` AND subdirs (`stub/`, `shipped/`, `deferred/`, `wontfix/`) for existing TKT-* IDs. Pick the next N sequential IDs for the N candidate tickets. Use the prefix and zero-padding width from `.claude/ticket-config.md`.
2. **Write epic file.** `{tickets-dir}/stub/EPIC-<slug>.md` with frontmatter (`status: stub`), north star, out of scope, member ticket list. Per the template in `brainstorm-mode.md`.
3. **Write ticket stubs.** One `{tickets-dir}/stub/TKT-NNN.md` per candidate, with frontmatter (`status: stub`, `epic: EPIC-<slug>`, `depends_on: [...]`), summary, acceptance criteria, notes. Per the template in `brainstorm-mode.md`.
4. **Write all files in one pass** before any commits land — so parallel sessions don't collide on IDs.

## Finish

Output a summary:

```
Brainstorm session complete — {N} ticket stubs written

Epic: EPIC-<slug> "{title}"   → {tickets-dir}/stub/EPIC-<slug>.md
Stubs:
  TKT-NNN  "{title}"
  TKT-NNN  "{title}"
  ...

Review the stubs in {tickets-dir}/stub/
Next: /ticket-promote TKT-NNN [TKT-MMM ...]  to move stubs into the active set (status: stub → open)
Then: /ticket-investigate <ID>  to plan a promoted ticket
```

If `--prowl` was passed, send a Prowl notification naming the epic and the count of stubs.

## Rules

- Do NOT write code. Not even examples.
- Do NOT produce implementation plans. That's `/ticket-investigate`'s job.
- Do NOT merge tangents silently. Capture them as stubs; the user decides what to defer later.
- Do NOT declare the session done. Wait for the user's signal.
- Do NOT create the output files until the user signals.
- Do NOT promote stubs yourself. That's a separate human-gated step via `/ticket-promote`.
