---
mode: agent
description: List active tickets (--all includes shipped/deferred/wontfix)
argument-hint: '[--all]'
---

# List Tickets

Show the current state of all tickets in the project.

## Input

Optional flag: `--all` — include terminal tickets (shipped, deferred, wontfix). Without the flag, only active tickets are shown.

## Pre-flight Checks

- If `.claude/ticket-config.md` does not exist, fall back to `tickets/` and `TKT-` as defaults.

## Steps

0. **Auto-reap preflight (silent):** Walk `.worktrees/ticket-*/`. For each worktree, extract the ticket ID and check whether the ticket file lives in a terminal subfolder or is missing. Remove the worktree and kill any preview PIDs for stale entries. If anything was reaped, print a single one-line note at the top ("auto-reaped N stale worktrees"). If nothing was reaped, say nothing.

1. **Read `.claude/ticket-config.md`** to find the tickets directory and ID prefix.

2. **Read `{PREFIX}*.md` files:**
   - **Default (active only):** only files at the root of `{tickets-dir}/` — do NOT recurse into `shipped/`, `deferred/`, `wontfix/`.
   - **With `--all`:** scan recursively including the three terminal subfolders; tag each ticket with its folder.

3. **Parse frontmatter** of each file: id, title, type, status, priority, branch.

4. **Group by status and display in a table:**

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

5. **Show a summary line:**
```
Active: {n} | Open: {n} | In Progress: {n} | Review: {n}
(with --all, also: | Shipped: {n} | Deferred: {n} | Wontfix: {n})
```

## Rules

- If the tickets directory is empty or missing, say "No tickets yet. Create one with /ticket-new {description}" (or "Run /ticket-install first" if `.claude/ticket-config.md` is missing).
- Sort by priority within each status group (critical > high > medium > low).
- Keep output concise.

## Compatibility Notes

- Auto-reap preflight: source behavior is an inline call to the `/ticket-cleanup` no-arg logic. In Copilot agent mode this is preserved as an explicit inline step rather than a slash command dispatch.
