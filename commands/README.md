# commands/

Claude Code universal slash commands. These files are symlinked into `~/.claude/commands/` by `install.sh`, which makes them available as slash commands in every Claude Code session on every machine.

## Files in this directory

Each file is a Claude Code slash command definition. The filename (minus `.md`) is the command name — `ticket-new.md` becomes `/ticket-new`.

| File | Command | What it does |
|---|---|---|
| `ticket-install.md` | `/ticket-install` | Bootstrap a project for the ticket workflow |
| `ticket-new.md` | `/ticket-new "title"` | Create a new ticket |
| `ticket-list.md` | `/ticket-list [--all]` | Show active tickets (pass `--all` for terminals too) |
| `ticket-investigate.md` | `/ticket-investigate TKT-NNN` | Explore code, write a plan into the ticket |
| `ticket-approve.md` | `/ticket-approve TKT-NNN` | Branch + implement the plan |
| `ticket-delegate.md` | `/ticket-delegate TKT-NNN [...]` | Delegate to another agent (default: full lifecycle, supports batch) |
| `ticket-collect.md` | `/ticket-collect TKT-NNN [...]` | Claude reviews delegated work (supports batch + consolidated checklist) |
| `ticket-status.md` | `/ticket-status [TKT-NNN]` | Show the lifecycle timeline of a ticket |
| `ticket-review.md` | `/ticket-review TKT-NNN` | Generate a human verification checklist |
| `ticket-preview.md` | `/ticket-preview TKT-NNN` | Launch the ticket's branch locally without shipping |
| `ticket-batch.md` | `/ticket-batch [IDs...]` | Run investigate + implement on many tickets in parallel worktrees |
| `ticket-chain.md` | `/ticket-chain [IDs...]` | Smart: parallel investigate, dependency detection, wave execute, preview + review checklist |
| `ticket-ship.md` | `/ticket-ship TKT-NNN` | Rebase, test, merge, deploy; archive to `tickets/shipped/` |
| `ticket-defer.md` | `/ticket-defer TKT-NNN {reason}` | Park a ticket in `tickets/deferred/` |
| `ticket-close.md` | `/ticket-close TKT-NNN {reason}` | Close as wontfix → `tickets/wontfix/` |
| `ticket-reopen.md` | `/ticket-reopen TKT-NNN` | Bring a terminal ticket back to active |
| `ticket-cleanup.md` | `/ticket-cleanup [ID\|--all]` | Reap stale worktrees + preview processes |

**Short aliases** are generated on each machine by `install.sh` from [`aliases.map`](aliases.map) — `/tn`, `/tl`, `/ts`, `/ti`, `/ta`, `/tr`, `/tp`, `/tb`, `/tch`, `/tsh`, `/td`, `/tc`, `/tro`, `/tcl`. The generated wrapper `.md` files are gitignored (they're real files, not symlinks — the harness dedupes symlinked commands to a single entry).

## Editing a command

Just edit the file. Commands are symlinked, so changes are live immediately on the edited machine:

```bash
vi commands/ticket-new.md      # or whichever command
git add commands/ticket-new.md
git commit -m "tweak ticket-new: better default priority inference"
git push
```

On other machines, `git pull` picks up the change. No `install.sh` re-run needed — the directory is symlinked.

## Adding a new command

Create a new file following the format of existing ones. The pattern is:

1. `# Command Title` (H1 header)
2. Short description of what it does
3. `## Input` — what arguments it expects
4. `## Pre-flight Checks` — what must be true before running
5. `## Steps` — the work, numbered
6. `## Rules` — constraints, do-nots, edge cases

The command file's content IS the prompt Claude Code uses when the slash command is invoked. Write it as if you're briefing a capable engineer: be specific, list preconditions, describe outputs precisely.

## For the full command reference

See [../docs/05-commands-reference.md](../docs/05-commands-reference.md) for a terse one-section-per-command reference, or [../docs/02-ticket-workflow.md](../docs/02-ticket-workflow.md) for the full lifecycle with examples.
