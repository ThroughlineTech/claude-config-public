---
description: '<machine> <repo> — register the dispatch target for this and future sessions'
argument-hint: '<machine> <repo>'
---

# Register intercom dispatch target

The user is registering a target machine and repo for subsequent `/send` and `/draft` dispatches. Registration persists to `~/.config/intercom/session` so it survives VS Code restarts.

Parse `$ARGUMENTS` as two whitespace-separated tokens: `<machine>` and `<repo>`.

If either token is missing, tell the user:
> Usage: `/register <machine> <repo>`. Use `/machines` to see available targets and `/repos <machine>` to see repos on a given machine.

Otherwise invoke Bash:

```
~/bin/intercom-session set "<machine>" "<repo>"
```

Then confirm to the user in one line: "Registered `<machine>/<repo>`. Use `/send <message>` or `/draft <description>` to dispatch."
