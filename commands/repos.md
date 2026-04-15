---
description: '<machine> [n] — list git repos on a remote intercom receiver (mtime-sorted, last n if given)'
argument-hint: '<machine> [n]'
---

# List repos on a remote intercom receiver

Parse `$ARGUMENTS`:
1. **machine** (required) — the target machine slug (e.g. `macmini`). Use `/machines` to see what's available.
2. **n** (optional) — cap at the last N repos touched by mtime. Default: list all.

If `machine` is missing, tell the user:
> Usage: `/repos <machine> [n]`. Run `/machines` first to see what receivers are online.

Otherwise invoke Bash:

```
~/bin/intercom-repos <machine> [n]
```

Print the helper's output verbatim inside a fenced code block. The table has NAME / PATH / MTIME columns; the `NAME` is the form usable in `/register <machine> <name>`. If the helper returns `(no response from <machine> in Ns ...)`, tell the user to check with `/machines` that the receiver is online.
