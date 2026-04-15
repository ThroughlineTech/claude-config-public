---
description: '<machine> <repo> — register the dispatch target for this and future sessions'
argument-hint: '<machine> <repo>'
---

# Register intercom dispatch target

The user is registering a target machine and repo for subsequent `/send` and `/draft` dispatches. Registration persists to `~/.config/intercom/session` so it survives VS Code restarts.

Parse `$ARGUMENTS` as two whitespace-separated tokens: `<machine>` and `<repo>`.

If no arguments are given, invoke Bash:

```
~/bin/intercom-session get
```

If the output contains `TARGET_MACHINE` and `TARGET_REPO`, report the current registration to the user:
> Registered: `<machine>/<repo>`

If there is no session registered, tell the user:
> No target registered. Use `/register <machine> <repo>` to set one.

Otherwise invoke Bash:

```
~/bin/intercom-session set "<machine>" "<repo>"
```

Then confirm to the user in one line: "Registered `<machine>/<repo>`. Use `/send <message>` or `/draft <description>` to dispatch."
