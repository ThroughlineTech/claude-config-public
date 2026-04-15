---
description: '<message> — dispatch message to the registered target'
argument-hint: '<message>'
---

# Send to registered target

Dispatch `$ARGUMENTS` as a prompt to the registered target (machine + repo) via the intercom stack.

Step 1: read the session by invoking Bash:

```
~/bin/intercom-session get
```

If this exits non-zero (no session registered), tell the user:
> No target registered. Run `/register <machine> <repo>` first (use `/machines` to see available targets).

Then stop.

Step 2: parse the output — it's KEY=VALUE lines with `TARGET_MACHINE` and `TARGET_REPO`. Invoke Bash, substituting the message verbatim (use the exact `$ARGUMENTS` text; do not rewrite or summarize):

```
~/bin/send-job "<TARGET_MACHINE>" "<TARGET_REPO>" "$ARGUMENTS"
```

Step 3: confirm to the user in one line: "Dispatched to `<machine>/<repo>`. Reply will surface on your next prompt."

Do not wait for the reply; the `UserPromptSubmit` hook surfaces it automatically.
