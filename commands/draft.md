---
description: '<description> — compose a prompt for the registered target, confirm, dispatch'
argument-hint: '<description of the work you want the remote agent to do>'
---

# Draft a prompt for the registered target

The user wants you to compose a clear, specific prompt for a remote Claude agent running in the registered target repo, then confirm before dispatching.

Step 1: read the session:

```
~/bin/intercom-session get
```

If it exits non-zero, tell the user to run `/register` first and stop.

Step 2: source the output to know `TARGET_MACHINE` and `TARGET_REPO`.

Step 3: compose a clear, actionable prompt based on `$ARGUMENTS`. The prompt should:
- be specific about what the remote agent should do (file paths, commands to run, expected output);
- include any context the remote agent would need that's obvious to you but not to a fresh session in the target repo;
- be self-contained (no references to this conversation).

Step 4: print the composed prompt to the user in a fenced code block so they can see exactly what will be sent. Then ask on the last line:

> Send this to `<TARGET_MACHINE>/<TARGET_REPO>`? (y/n)

Step 5: **STOP.** Do not dispatch yet. The user's NEXT message is the confirmation.

When the user replies:
- `y` / `yes` / `ok` / `send` → invoke Bash `~/bin/send-job "<TARGET_MACHINE>" "<TARGET_REPO>" "<the composed prompt text>"`, then say "Dispatched. Reply will surface on your next prompt."
- `n` / `no` / `cancel` → say "Cancelled, not sent." and stop.
- anything else → briefly ask again (y/n).

If the user wants to tweak the prompt instead of answering y/n, treat it as a revision and re-enter step 3 with the new guidance.
