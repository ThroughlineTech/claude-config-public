---
description: 'TKT-XXX [TKT-YYY ...] | --all — promote stub tickets to the active set (stub → open)'
argument-hint: 'TKT-XXX [TKT-YYY ...] | --all'
---

# Promote Stub Tickets

Move one or more ticket stubs from `{tickets-dir}/stub/` into the active `{tickets-dir}/` and flip `status: stub → open`. This is the human gate between "someone brainstormed this" and "this is work we're committing to investigate."

## Input

Parse flags first:
- `--all` — promote every `TKT-*.md` stub AND every `EPIC-*.md` file in `{tickets-dir}/stub/`.

Remaining arguments are ticket IDs. Resolution rules:
- **Fully-qualified IDs** (e.g., `TKT-102a`) match exactly: `TKT-102a.md`.
- **Bare numbers** (e.g., `102`) resolve as a prefix match: include the canonical `TKT-<padded>.md` (using the prefix and zero-padding from `.claude/ticket-config.md`) plus any letter-suffix variants (`TKT-102a.md`, `TKT-102b.md`, ...). Do NOT match other numeric variants like `TKT-1020.md` — the numeric part must match exactly.

If `--all` is given, explicit IDs are ignored. Zero IDs and no `--all` → error.

## Pre-flight

- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- `{tickets-dir}/stub/` must exist. If not, report that there are no stubs to promote and stop.

## Steps

**1. Resolve the set of tickets to promote.**

Expand each argument to matching files in `{tickets-dir}/stub/`:
- Fully-qualified ID → exactly `TKT-<ID>.md`.
- Bare number → `TKT-<padded>.md` plus any `TKT-<padded>[a-z]+.md` variants.
- `--all` → every `TKT-*.md` in `stub/`.

If any explicit argument resolves to zero files, report it and stop.

**2. Collect referenced epics.**

For each matched ticket, read its `epic:` frontmatter field. Gather the unique set of epic slugs. For each, the epic file is `{tickets-dir}/stub/EPIC-<slug>.md`. If `--all` was given, also include every `EPIC-*.md` in `stub/` regardless of ticket references.

The referenced epics are promoted alongside the tickets because `/ticket-investigate` looks for the epic in the **same directory** as the ticket. Leaving the epic in `stub/` after the ticket moves to active would break that lookup.

**3. Promote each file (tickets first, then epics).**

For each file:
1. Verify it's in `{tickets-dir}/stub/`. If not (e.g., already promoted or in a terminal subfolder), skip with a notice — don't error.
2. Verify `status: stub` in the frontmatter. If different, skip with a notice.
3. Move the file: `mv {tickets-dir}/stub/<name>.md {tickets-dir}/<name>.md`.
4. Update the frontmatter: `status: stub` → `status: open`, set `updated: <today>`.

Each epic is promoted at most once per call, even if referenced by multiple tickets.

## Output

```
Promoted {N} tickets + {M} epics to open:
  Tickets:
    TKT-102a  "{title}"
    TKT-102b  "{title}"
    ...
  Epics:
    EPIC-voice-ux  "{title}"

Skipped {K}: {reasons}

Next: /ticket-investigate TKT-102a [TKT-102b ...]  to investigate
Or:   /ti TKT-102a TKT-102b TKT-102c                to investigate several in order
```

If no epics were referenced, omit the Epics block. If nothing was skipped, omit the Skipped line.

## Rules

- Only promote files whose frontmatter reads `status: stub`. Skip others with a notice (don't error unless the whole call resolved to zero files).
- Do NOT touch files in the active set or terminal subfolders.
- Do NOT investigate; promotion is a status flip + file move only.
- Epics referenced by promoted tickets are auto-promoted so `/ti`'s same-directory epic lookup works. An epic is moved once per call even if referenced by multiple tickets.
