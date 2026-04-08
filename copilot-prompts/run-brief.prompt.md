---
mode: agent
description: Execute a Claude Code delegation brief
---

You are executing a delegation brief written by Claude Code. The user will give you a path to a brief file like `tickets/TKT-XXX.{phase}.brief.md`. If they don't, find the most recently modified `tickets/TKT-*.brief.md` file in the workspace.

Steps:
1. Read the brief file completely. It contains everything you need: who you are, what files to read, what to do, what NOT to do, what to write, and what status transitions are expected.
2. Read every file the brief lists under "Files to read first" before doing anything else.
3. Follow the brief's instructions exactly. Do not improvise outside its scope.
4. Write the requested output (code changes, ticket section updates, peer review, etc.) as the brief specifies.
5. When done, output a one-line summary in this exact format:

   `Brief executed: {brief filename}. Hand back to Claude Code with: /ticket-collect {TKT-ID}`

If you get stuck or the brief seems wrong, stop and tell the user — don't guess. The brief is meant to be self-contained; if something feels missing, that's a real signal worth raising.

Hard rules (apply to every brief unless the brief explicitly says otherwise):
- Never merge to main
- Never deploy
- Never change branches
- Never push tags
- Never touch files unrelated to the brief's scope
- Never modify other tickets' files
