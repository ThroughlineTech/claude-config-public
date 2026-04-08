# FAQ

Questions future-you is likely to ask.

## General

### What is this repo, in one sentence?
Personal dotfiles for Claude Code and Copilot Chat, plus a universal ticket workflow, plus a cross-model delegation system, all syncable between machines via git. See [00-overview.md](00-overview.md).

### Why did I build this?
See [00-overview.md](00-overview.md) for the full problem framing. Short version: before this, Claude Code config and ticket workflows were per-machine and per-project, Copilot didn't share context with Claude Code, and there was no clean way to mix models for different tasks. This repo fixes all of that.

### Should this fork be private or public?
The public template ships with no secrets and no personal data, so it's safe to fork publicly as-is. Whether YOUR fork should stay public depends on what you add to it — see "Secrets and privacy" below.

### Can I delete this repo and start over?
Sure, but why? The state in it is useful. If you mean "I want to rebuild the structure from scratch," you can, but the cost is re-writing all the commands and templates, and you'd lose the plan history. Better to edit in place.

## Installation

### Do I need to re-run `install.sh` after every git pull?
Only if the pull touched `CLAUDE.md` or a `settings.*.json` file. Everything else is live via symlinks. See [07-editing-and-syncing.md](07-editing-and-syncing.md) for the matrix.

### Is `install.sh` safe to re-run?
Yes. It's idempotent. Re-running it:
- Leaves correct symlinks alone
- Replaces wrong or missing symlinks (backing up the old target)
- Regenerates `~/.claude/settings.json` from the source files
- Regenerates `copilot-prompts/claude-global.instructions.md` from `CLAUDE.md`
- Re-runs smoke tests

Worst case, it's a 3-second no-op.

### I ran `install.sh` and my 200 accumulated permission grants are gone. Are they lost?
No — they're backed up to `~/.claude/settings.json.backup.{timestamp}`. See [08-troubleshooting.md](08-troubleshooting.md) for how to mine the backup for patterns worth promoting into the repo.

### Can I run this on a machine that already has Claude Code set up?
Yes. `install.sh` backs up any existing `~/.claude/CLAUDE.md`, `~/.claude/commands/`, `~/.claude/plans/`, `~/.claude/brief-templates/`, and `~/.claude/settings.json` to `*.backup.{timestamp}` files before replacing them. Nothing is deleted; everything is recoverable.

### Does this work on WSL?
It should — `install.sh` treats WSL as Linux and installs into the WSL filesystem's `~/.claude/`. That means Claude Code running inside WSL will see the config; Claude Code running on Windows-native won't. If you want both, install twice (once in WSL, once in Git Bash).

### Does this work on Linux?
Should work. Untested as a primary environment but the scripts handle it (`case "$(uname -s)" in Linux) ...`). The settings merge uses `settings.mac.json` as the platform file on Linux, since the Linux tool names overlap more with Mac than Windows. If you need Linux-specific allows, add a `settings.linux.json` and update `install.sh` to pick it.

## Daily use

### How do I create a new ticket?
In any bootstrapped project: `/ticket-new "short description"`. If the project isn't bootstrapped, run `/ticket-install` first.

### How do I bootstrap a new project for tickets?
In the project directory, start a Claude Code session, run `/ticket-install`. It detects the stack, proposes commands, asks you to confirm, writes `tickets/TEMPLATE.md` and `.claude/ticket-config.md`, and appends a `## Tickets` section to the project's `CLAUDE.md`.

### How do I see what's in flight across all my tickets?
`/ticket-list` in the project. For a single ticket's full history, `/ticket-status TKT-005`.

### How do I hand a ticket off to a different model?
`/ticket-delegate TKT-005 implement` (or `investigate`, `review`, or `verify <phase>`). See [03-delegation.md](03-delegation.md) for the full flow.

### How do I edit the global instructions (CLAUDE.md)?
Edit the file at `~/src/claude-config/CLAUDE.md`. Commit. Push. On each machine, `git pull && bash install.sh` (re-install because the Copilot instructions file is regenerated from CLAUDE.md).

### Can I have project-specific instructions that override the global CLAUDE.md?
Yes — create a `CLAUDE.md` in the project root. Claude Code reads the project-level file in addition to the global one. Project rules take precedence on conflicts.

### Can I add a custom slash command that's only for one project?
Yes — put it in `.claude/commands/` inside the project (not in `~/.claude/commands/`). Project-scoped commands shadow user-scoped ones with the same name.

## Cross-model delegation

### Why can't Claude Code call Gemini directly?
No API bridge from Claude Code into VS Code Copilot Chat. The handoff has to go through the filesystem. See [03-delegation.md](03-delegation.md) for the design decision.

### Do I have to use Gemini specifically?
No. Any model in Copilot Chat can execute a brief — Gemini, GPT, Claude, whatever's there. The brief format is model-agnostic.

### Can I review Claude Code's work with another Claude Code session?
Technically yes, but it defeats the purpose. The value of peer review is getting a *different* model's perspective. Two Claude Code sessions will tend to agree with each other because they're the same model with the same biases.

### What if the executing agent returns broken code?
You find out during `/ticket-review` or when you manually verify. Options: fix it yourself (in either tool), re-delegate with a more specific brief, or abandon the ticket and investigate why the delegation failed. The broken code is contained to the feature branch; main is unaffected.

### Can I delegate to two models in parallel and compare?
Not currently. The ticket status flow assumes one delegation at a time. You could manually generate two briefs (one for each model), have both execute in separate Copilot Chat tabs, and compare the results, but `/ticket-collect` would only expect one. This is an area for future tooling.

## Secrets and privacy

### This is the public template — what's already been removed?
The template ships with NO secrets and NO personal data. Specifically:
- **No API keys** — `CLAUDE.md` is a customize-me template that describes the push notification pattern but tells you to add your own key
- **No plans** — `plans/` is empty (just a `.gitkeep`)
- **No project-specific allows** — `settings.{base,mac,windows}.json` contain only universal patterns; no references to specific projects, paths, or services
- **No commit history with personal info** — the public template starts from a fresh `git init`

### Should I make MY fork public or private?
Depends on what you put in it.

- **Make it private if**: you commit API keys directly to `CLAUDE.md`, you commit plan files with project-specific design work, or you add settings entries that reveal private project paths.
- **Make it public if**: you keep secrets in `~/.claude/secrets.md` (which is gitignored and lives outside the repo), you don't commit plans, and you keep settings entries to broad patterns that don't reveal personal info.

If in doubt, **start private**. You can always go public later by extracting secrets and rewriting history. Going from public to private after a leak is much harder.

### How do I handle secrets without committing them?
Create `~/.claude/secrets.md` on each machine manually (it's already in `.gitignore`, so it'll never accidentally get committed). Store API keys, tokens, etc. there. In `CLAUDE.md`, instead of pasting the key directly, write something like:

```
The push notification API key is in ~/.claude/secrets.md under "Notifications".
Read that file when you need to send a notification.
```

Claude Code and Copilot can read `~/.claude/secrets.md` like any other file. The file isn't synced between machines — you set it up manually per machine — but the *reference* to it lives in the synced `CLAUDE.md`, so the convention propagates.

### What if my API key leaks?
Rotate it. Generate a new key with your provider, update `CLAUDE.md` (or `~/.claude/secrets.md` if you used the secrets file approach) with the new key, commit (only if it's the secrets file path that changed, not the key itself), push, re-install on every machine. The blast radius of a leaked notification key is limited — usually just "spam to your phone until you rotate" — but rotate as soon as you notice exposure.

### Git commit history has my email and name — is that a problem?
For a public repo: maybe. Your name and email are in every commit you make. If you don't want that publicly searchable, configure git to use a privacy-preserving email (GitHub provides one at `<id>+<username>@users.noreply.github.com`):

```bash
git config user.email "12345+yourusername@users.noreply.github.com"
git config user.name "Your Public Name"
```

Set this per-repo (not global) so your other repos still use your real email.

### How do I clean an existing repo of secrets I accidentally committed?
Three options, in increasing order of effort:

1. **Rotate the leaked secret immediately.** Even before cleanup. Assume anything pushed publicly is permanently leaked.
2. **Remove from current state**: `git rm <file> && git commit -m "remove leaked secret" && git push`. The file is gone from the working tree but still in history.
3. **Nuke from history**: use `git filter-repo` (modern) or BFG Repo-Cleaner. Read the docs carefully — these rewrite history and require force-pushing.

If the secret is in the most recent commit only, you can amend: `git rm <file> && git commit --amend && git push --force`. Don't force-push to a branch others have pulled.

## Sync and backup

### What happens if I edit a plan on both machines at the same time?
Git will refuse the pull with a conflict message. You resolve it like any other conflict: decide which version to keep (or merge them by hand), commit, push. Plans have unique auto-generated filenames so collisions on specific plan files are rare; the main collision risk is `_next.md` (fixed name) — but `claude-handoff` always overwrites it intentionally, so whichever machine pushed last wins, which is what you want.

### I lost the repo on one machine. How do I recover?
`git clone git@github.com:<you>/claude-config.git ~/src/claude-config && cd ~/src/claude-config && bash install.sh`. Your Mac and your GitHub remote are the authoritative copies; losing one machine's clone is a non-event.

### I pushed something I shouldn't have. How do I remove it?
Option 1 (preserve history): `git rm <file> && git commit -m "remove {thing}" && git push`. The file is gone from the working tree but still in history.

Option 2 (nuke from history): `git filter-repo` or BFG Repo-Cleaner. Nuclear option for secrets that must not be in the git history at all. Read the git docs carefully before using.

### Should I back up the repo somewhere other than GitHub?
GitHub is fine for a private repo — you're effectively using GitHub as both sync and backup. If you're paranoid, clone it to an external drive occasionally. The repo is small (under 10MB including docs) so backup is cheap.

## Maintenance and hygiene

### How often should I review the settings.json backups and delete them?
See [11-maintenance.md](11-maintenance.md). Short answer: delete redundant backups (plans.backup, commands.backup, CLAUDE.md.backup) a week after install once you've verified nothing is lost. Keep settings.json.backup longer (a month+) in case you need to mine it for promoted grants.

### Should I commit `_next.md` to the repo?
Yes. It's a pointer file — the whole point is that it's synced so the other machine can find the latest plan. The `.gitignore` explicitly allows it.

### The accumulated allows in my local settings.json keep growing. How do I prevent bloat?
You don't — each new grant is Claude Code being cautious, which is good. When the list gets long enough that you notice it slowing things down (or when you spot recurring patterns), dedicate 10 minutes to promoting the common ones into `settings.base.json` or the platform file. Then re-install; the bloat goes to the backup file and you start fresh.

### How do I keep the docs up to date?
You don't need to do it continuously. The docs describe the architecture, which changes rarely. When you make a meaningful change, update the relevant doc at the same time. Set a personal rule: "any PR that changes behavior also updates docs" (even if you're solo and the PR is a direct commit).

## Advanced

### Can I use this with Cursor / Aider / other editors?
The `CLAUDE.md` and ticket files are plain markdown — any tool that reads them will work. The slash commands are Claude-Code-specific. The Copilot prompts are VS-Code-Copilot-specific. Cursor has its own rules system (`.cursorrules`) which you could generate from `CLAUDE.md` the same way we generate the Copilot instructions file. That'd be a small addition to `install.sh`.

### Can I share this with a colleague?
Yes — that's exactly what this public template is for. Point them at the repo, they fork it, customize `CLAUDE.md` for their own preferences, run `bash install.sh`, and they're set. The infrastructure is fully transferable; only the customizations are personal.

### How do I add a new brief template for a phase I just invented?
Create `brief-templates/{phase}.md` (use existing templates as a model). Update `commands/ticket-delegate.md` to know about the phase (add it to the phase-specific preconditions table and any placeholder substitution logic). Commit, push, pull on other machines. No install re-run needed — templates are symlinked.

### Can I disable parts of this on specific machines?
In principle yes — you could skip the Copilot wiring if you don't use VS Code on that machine. In practice, `install.sh` already does this automatically (it checks if VS Code is installed and skips if not). If you need finer-grained control, you'd need to pass flags to `install.sh` — something like `--no-copilot` — which is a small change to add.

### What happens when Claude Code updates and breaks a slash command format?
Edit the affected command file in `commands/` to match the new format. Commit, push, pull on other machines. Because commands are symlinked, every machine picks up the fix without re-install.

### Can I run multiple versions of the repo?
Not recommended. The symlinks in `~/.claude/` all point at whatever path `install.sh` was last run from. If you want to test a branch without affecting the installed version, work in a worktree: `git worktree add ../claude-config-test some-branch`, and don't run `install.sh` from the worktree.

### How do I add a `/ticket-*` command for my own needs?
Same process as any other command edit. Create `commands/ticket-yourcommand.md` with the command definition (see existing commands for the format). Commit, push, pull. It'll be available in Claude Code in every project on every machine as `/ticket-yourcommand`.
