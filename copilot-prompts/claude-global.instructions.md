---
applyTo: "**"
---

# Global Agent Configuration

This file is loaded by every Claude Code session and (if configured) by Copilot Chat. It contains conventions every agent — Claude Code, Copilot/Gemini, GPT, etc. — should follow regardless of project or machine.

## Prowl Push Notifications (any agent, any tool)

When the user says "prowl" (e.g., "prowl me when done", "send me a prowl", "prowl me if it breaks"), send an iOS push notification via the Prowl API. This is how agents communicate with Dan when he's away from the machine. Use this freely — it's exactly what the channel exists for.

**API key:** `YOUR_PROWL_API_KEY_HERE`

**Mac / Linux / WSL:**
```bash
curl -s https://api.prowlapp.com/publicapi/add \
  -d "apikey=YOUR_PROWL_API_KEY_HERE" \
  -d "application=APP_NAME" \
  -d "event=TITLE" \
  -d "description=DETAILS" \
  -d "priority=0"
```

**Windows PowerShell:**
```powershell
Invoke-RestMethod -Method POST -Uri 'https://api.prowlapp.com/publicapi/add' `
  -Body 'apikey=YOUR_PROWL_API_KEY_HERE&application=APP_NAME&event=TITLE&description=DETAILS&priority=0' `
  -ContentType 'application/x-www-form-urlencoded'
```

**Priority levels:** -2 (very low), -1 (low), 0 (normal), 1 (high), 2 (emergency)

**Application name** should identify *what* is notifying — combine the agent and project so it's scannable on the lock screen:
- `Claude Code: rejog-ios`
- `Gemini: throughline-v2`
- `ticket-ship: mac-remote-deploy`

**Common patterns:**
- "send me a test prowl" → `event=Test`, `description=Prowl is working from {agent}/{project}`
- "do X and prowl me when done" → do the work, then `event=Ready for Review`, `description=summary of what was done`
- "prowl me if something breaks" → on failure, `event=Build Failed` (priority=1), `description=what went wrong`

## Plan Mode

**If you enter plan mode — or are writing to an on-disk plan file — read `plan-mode.md` before presenting or editing the plan.** That file has the scope, subtraction, rescope, and ship-gate rules. They are not optional.

## Brainstorm Mode

**If you enter a brainstorm session (e.g., via `/brainstorm`), read `brainstorm-mode.md` before starting.** That file governs a different phase than plan mode: it produces scoped ticket stubs (not plans, not code). Its rules are not optional. The two modes must not be confused.

## Universal Conventions

These apply to any project unless the project's own `CLAUDE.md` overrides them.

- **Commit message format:** `{TKT-ID}: short description` when working on a ticket; `topic: short description` otherwise. Follow each project's git log style if it's clearly different.
- **No Claude branding in commits.** Do not add `Co-Authored-By: Claude` trailers or "Generated with Claude Code" lines to commit messages or PR bodies.
- **Don't merge or deploy without explicit instruction.** Implementing a fix is one thing; pushing to main and shipping is a separate, explicit step (`/ticket-ship`).
- **When you finish a long task, prowl the user and stop.** Don't keep working past the requested scope.
- **`--prowl` is a universal opt-in flag.** Any slash command or freeform request can include `--prowl` as an argument. When present, send a Prowl notification at the end of the task (summary + success/failure) regardless of whether that command normally prowls. If the command already prowls by default (e.g., `/tch`, `/tb`, `/tp`, `/ticket-collect`), `--prowl` is a no-op — don't double-prowl.
- **Read before writing.** Don't propose changes to code you haven't read.
- **Tickets are the system of record.** If a project has `tickets/`, the ticket file is the canonical record of what was decided and why. Keep it updated as you work.
