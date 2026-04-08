# Global Agent Configuration

This file is loaded by every Claude Code session and (if configured) by Copilot Chat. It contains conventions every agent — Claude Code, Copilot/Gemini, GPT, etc. — should follow regardless of project or machine.

> **This is the public template.** Customize the sections below for yourself, then re-run `bash install.sh` to regenerate the Copilot instructions file from your edited content. Anything you put in `CLAUDE.md` is loaded by both Claude Code and Copilot Chat in every project on every machine.

## Push Notifications (any agent, any tool) — TEMPLATE, customize me

When the user says a recognizable trigger word ("ping me", "notify me", "tell me when done"), send a push notification to their phone via whatever notification service they've set up.

### How to set this up

This template assumes you'll wire up a push channel of your own choice. Common options:

- **[Prowl](https://www.prowlapp.com/)** — iOS push notifications via REST API. Free for personal use.
- **[Pushover](https://pushover.net/)** — iOS + Android push notifications via REST API.
- **[ntfy.sh](https://ntfy.sh/)** — Open-source push notifications, self-hostable.
- **Slack incoming webhook** — if you live in Slack
- **Discord webhook** — if you live in Discord
- **Telegram bot** — if you live in Telegram

Pick one, get an API key or webhook URL, and replace this section with the curl command and credentials. **Do not commit your API key to a public repo** — see "Where to put secrets" below.

### Example: Prowl (replace with your chosen service)

```bash
curl -s https://api.prowlapp.com/publicapi/add \
  -d "apikey=YOUR_PROWL_API_KEY_HERE" \
  -d "application=APP_NAME" \
  -d "event=TITLE" \
  -d "description=DETAILS" \
  -d "priority=0"
```

**Application name** should identify *what* is notifying — combine the agent and project so it's scannable on the lock screen:
- `Claude Code: my-project-name`
- `Gemini: my-other-project`
- `ticket-ship: backend-api`

**Common patterns:**
- "test notification" → `event=Test`, `description=Notifications working from {agent}/{project}`
- "do X and notify me when done" → do the work, then `event=Ready for Review`, `description=summary`
- "notify me if something breaks" → on failure, `event=Build Failed` (high priority), `description=what went wrong`

### Where to put secrets

You have two options:

1. **Private repo (simplest)**: fork this repo, make your fork private, paste your API key directly into this file. It's never published.
2. **Public-friendly secrets file**: create `~/.claude/secrets.md` (already in `.gitignore`) on each machine, store your key there, and update the section above to reference it: "the API key is in `~/.claude/secrets.md` under 'Notifications'." `~/.claude/secrets.md` lives outside the repo and is set up manually per machine.

If you're going to keep this repo public, use option 2.

## Universal Conventions — TEMPLATE, customize me

These apply to any project unless the project's own `CLAUDE.md` overrides them. Edit, remove, or add as you see fit.

- **Commit message format:** `{TKT-ID}: short description` when working on a ticket; `topic: short description` otherwise. Follow each project's git log style if it's clearly different.
- **No tool branding in commits.** Do not add `Co-Authored-By: Claude` trailers, "Generated with Claude Code" lines, or similar agent attribution to commit messages or PR bodies. Commits should look like the human authored them.
- **Don't merge or deploy without explicit instruction.** Implementing a fix is one thing; pushing to main and shipping is a separate, explicit step (`/ticket-ship`).
- **When you finish a long task, send a notification and stop.** Don't keep working past the requested scope.
- **Read before writing.** Don't propose changes to code you haven't read.
- **Tickets are the system of record.** If a project has `tickets/`, the ticket file is the canonical record of what was decided and why. Keep it updated as you work.

## What to do next

After customizing this file:

```bash
cd ~/src/claude-config         # or wherever you cloned this
bash install.sh                # regenerates copilot-prompts/claude-global.instructions.md
git add CLAUDE.md
git commit -m "Customize CLAUDE.md for me"
```

If your repo is private and you committed an API key directly, you're done. If your repo is public and you used the secrets-file approach, also create `~/.claude/secrets.md` with your actual key.

Your edits are now loaded by every Claude Code session and Copilot Chat conversation on this machine, in every project. Sync to other machines with `git push` here, `git pull && bash install.sh` there.
