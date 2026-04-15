---
description: 'list connected intercom receivers'
---

# List intercom receivers

Invoke Bash `~/bin/intercom-machines` and print its output verbatim to the user inside a fenced code block. The helper publishes a query and collects responses for ~2 seconds, so do not run it more than once per invocation.

If the helper returns `(no intercom receivers responded in Ns)`, tell the user: "No intercom receivers responded. Check that the Mac receiver is loaded (`ssh mac launchctl list | grep intercom`) and that you're on the same Tailnet."
