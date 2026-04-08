# List Tickets

Show the current state of all tickets in the project.

## Steps

1. Read `.claude/ticket-config.md` to find the tickets directory and ID prefix (default: `tickets/`, `TKT-`). If the config doesn't exist, fall back to `tickets/` and `TKT-`.
2. Read all `{PREFIX}*.md` files from the tickets directory.
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

### Shipped
| ID | Title | Type | Shipped |
|----|-------|------|---------|
```

5. Show a summary line:
```
Total: {n} | Open: {n} | In Progress: {n} | Review: {n} | Shipped: {n}
```

## Rules
- If the tickets directory is empty or missing, say "No tickets yet. Create one with /ticket-new {description}" (or "Run /ticket-install first" if `.claude/ticket-config.md` is missing).
- Sort by priority within each status group (critical > high > medium > low)
- Keep output concise
