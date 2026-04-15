---
description: '[--all] — list active tickets (--all includes shipped/deferred/wontfix)'
argument-hint: '[--all]'
---

# List Tickets

Show the current state of all tickets in the project.

## Input

Optional flag: `--all` — include terminal tickets (shipped, deferred, wontfix). Without the flag, only active tickets are shown.

## Steps

0. **Auto-reap preflight (silent):** run the `/ticket-cleanup` no-arg logic inline — walk `.worktrees/ticket-*/`, reap any whose ticket is in a terminal folder or missing. If anything was reaped, print a single one-line note at the top of the output ("auto-reaped N stale worktrees"). If nothing was reaped, say nothing.
1. Read `.claude/ticket-config.md` to find the tickets directory and ID prefix (default: `tickets/`, `TKT-`). If the config doesn't exist, fall back to `tickets/` and `TKT-`.
2. Read `{PREFIX}*.md` files:
   - **Default (active only):** only files at the root of `{tickets-dir}/` (do NOT recurse into `shipped/`, `deferred/`, `wontfix/`).
   - **With `--all`:** scan recursively, including the three terminal subfolders. Tag each ticket with its folder so the renderer knows where it lives.
3. Parse the frontmatter of each to extract: id, title, type, status, priority, branch.
4. Group by status and display in a table:

```
## Tickets

### Open
| ID | Title | Type | Priority |
|----|-------|------|----------|

### Investigating / Proposed
| ID | Title | Type | Priority | Branch |
|----|-------|------|----------|--------|

### In Progress
| ID | Title | Type | Priority | Branch |
|----|-------|------|----------|--------|

### In Review
| ID | Title | Type | Priority | Branch |
|----|-------|------|----------|--------|

### Shipped    (only shown with --all)
| ID | Title | Type | Shipped |
|----|-------|------|---------|

### Deferred   (only shown with --all)
| ID | Title | Type | Reason |
|----|-------|------|--------|

### Wontfix    (only shown with --all)
| ID | Title | Type | Reason |
|----|-------|------|--------|
```

5. Show a summary line:
```
Active: {n} | Open: {n} | In Progress: {n} | Review: {n}
(with --all, also: | Shipped: {n} | Deferred: {n} | Wontfix: {n})
```

## Rules
- If the tickets directory is empty or missing, say "No tickets yet. Create one with /ticket-new {description}" (or "Run /ticket-install first" if `.claude/ticket-config.md` is missing).
- Sort by priority within each status group (critical > high > medium > low)
- Keep output concise
