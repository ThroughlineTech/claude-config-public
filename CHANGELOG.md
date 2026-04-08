# Changelog

All notable changes to `claude-config`. Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [0.1.0-public] — 2026-04-07

Public template version. Extracted from a personal `claude-config` repo with all secrets, plans, and project-specific content removed. `CLAUDE.md` is a customize-me template; the rest is a turnkey workflow you can install and use immediately.

To use: fork the repo, customize `CLAUDE.md` for yourself, run `bash install.sh`. See [README.md](README.md) for the quickstart.

## [0.1.0] — 2026-04-07

Initial version. Everything is new.

### Added

- **Universal ticket workflow** — 10 slash commands (`/ticket-*`) available in every project on every machine, stack-agnostic (reads build/test/deploy commands from per-project `.claude/ticket-config.md`).
- **`/ticket-install`** — bootstrap any project (new or existing) into the ticket workflow. Detects stack (Node, Rust, Go, Swift/Xcode, Python, Ruby, Java, Make), proposes commands, writes `tickets/TEMPLATE.md` and `.claude/ticket-config.md`, appends a `## Tickets` section to the project's `CLAUDE.md`.
- **Cross-model delegation system** — `/ticket-delegate` generates a self-contained markdown brief for a phase; any model in Copilot Chat can execute the brief via the `/run-brief` Copilot prompt; `/ticket-collect` picks up the returned work. Six brief templates cover investigate, implement, review, and peer-review variants.
- **Global `CLAUDE.md`** — single source of truth for agent instructions, loaded automatically by both Claude Code (via `~/.claude/CLAUDE.md` symlink) and Copilot Chat (via generated `claude-global.instructions.md` in VS Code's user prompts directory). Currently documents the Prowl push notification channel and universal agent conventions.
- **Three-layer Claude Code settings** — `settings.base.json` (universal: broad allows like `Bash(git:*)`, safety denies, env vars, `effortLevel: max`), `settings.mac.json` (Xcode/Swift/xcrun), `settings.windows.json` (PowerShell/WSL/cmd.exe). `install.sh` merges the base with the platform-specific file via `jq` on each install.
- **`install.sh`** — idempotent installer. Symlinks four paths into `~/.claude/` (`CLAUDE.md`, `commands/`, `plans/`, `brief-templates/`), merges settings, generates and symlinks the Copilot instructions file, wires VS Code user prompts, adds `bin/` to PATH (supports `.bashrc` and `.zshrc`), runs smoke tests. Backs up anything it would replace with a timestamped suffix.
- **`preflight.sh`** — read-only pre-install safety check. Verifies platform, required tools, symlink capability (catches the Windows MSYS "fake symlink" failure mode), repo completeness, existing `~/.claude/` state, VS Code detection, shell rc file, and git config. Exits 0 on safe-to-install, 1 on blocking failures.
- **`bin/claude-handoff`** — plan handoff script. Copies the most recent plan to `plans/_next.md`, commits, and pushes. On the other machine, `git pull` surfaces the plan at `~/.claude/plans/_next.md` for execution.
- **Synced `plans/` directory** — symlinked into `~/.claude/plans/` on every machine, so plans written on one machine are visible on every other machine after a `git pull`.
- **Windows support in Git Bash** — install.sh exports `MSYS=winsymlinks:nativestrict` to force real Windows symlinks (requires Developer Mode or admin shell). Preflight diagnoses and explains the fix if symlinks fail.
- **Comprehensive documentation** — `README.md` plus 12 docs in `docs/` covering overview, install, workflow, delegation, architecture, commands reference, new machine setup, editing and syncing, troubleshooting, FAQ, design decisions, and maintenance cadence.

### Known limitations

- **`settings.json` accumulated permission grants** are regenerated on every `install.sh` run. If you approve a one-shot grant during daily work, it lives in `~/.claude/settings.json` only until the next install, at which point it's wiped (and backed up). Promote recurring patterns to `settings.{base,mac,windows}.json` in the repo to persist them across installs.
- **Per-project memory** (`~/.claude/projects/*/memory/`) is not synced between machines — it's machine-local by design. If you want cross-machine memory for a specific project, commit that project's memory into its own repo.
- **Push notification setup is BYO**. The public template's `CLAUDE.md` describes the pattern but doesn't ship with a working API key. You provide your own (Prowl, Pushover, ntfy.sh, Slack, Discord, Telegram, etc.) and either commit it directly to a private fork or store it in a gitignored `~/.claude/secrets.md`.

## Release notes format

When adding entries in the future, use these categories as needed:

- **Added** — new features
- **Changed** — changes to existing features
- **Deprecated** — features that still work but will be removed later
- **Removed** — features removed
- **Fixed** — bug fixes
- **Security** — anything related to credentials, permissions, or deny lists
