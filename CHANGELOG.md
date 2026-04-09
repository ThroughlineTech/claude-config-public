# Changelog

All notable changes to `claude-config`. Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [0.2.2-public] — 2026-04-09

### Added

- **`/ticket-chain`** — sequential investigate → approve → ship pipeline. Unlike `/ticket-batch` (parallel worktrees, stops at preview), chain mode processes tickets one at a time, shipping each to main before starting the next. Auto-approves unless `Regression Risk: high`. Failures stop the chain (since later tickets may depend on earlier ones). `--dry-run` flag investigates all tickets without implementing. Alias: `/tch`.
- **Command frontmatter** restored — every `/ticket-*` command has `description` and `argument-hint` fields so the slash-command picker shows what the command does and the expected arguments inline.
- **Short aliases via real-file wrappers** — `install.sh` generates gitignored real `.md` wrapper files from `aliases.map` instead of symlinks. The Claude Code harness dedupes symlinked commands to a single entry, hiding either the alias or the canonical — real files avoid this.

### Fixed

- **`/ticket-batch` worktree sync-back** — after Phase 4 subagents complete, ticket files that reached `proposed` or `review` status are now copied from `.worktrees/ticket-{id}/tickets/{ID}.md` back to `tickets/{ID}.md` in the main working directory, staged, and committed. Previously the main branch copies remained stale after a batch investigation because subagents only wrote to their worktree copies.
- **Stale alias descriptions and missing commands in READMEs** — commands/README.md and main README.md updated to reflect the full v0.2.0 command set and real-file alias approach.

## [0.2.1-public] — 2026-04-08

### Added

- **Command frontmatter** — every `/ticket-*` command has `description` and `argument-hint` fields so the slash-command picker shows what the command does and the expected arguments inline, instead of just the bare name.
- **Short aliases** — `commands/aliases.map` defines single-letter/short aliases (`/tn`, `/tl`, `/ts`, `/ti`, `/ta`, `/tr`, `/tp`, `/tb`, `/tsh`, `/td`, `/tc`, `/tro`, `/tcl`). `install.sh` reads the map and creates gitignored symlinks in `commands/` on each machine, so aliases propagate with a `git pull + bash install.sh` and don't pollute the repo. Stale aliases removed from the map are reaped on the next install.

## [0.2.0-public] — 2026-04-08

Major expansion of the ticket workflow: terminal-state management, preview-before-ship, and parallel batch mode. Existing projects can upgrade via `/ticket-install` in update mode — it migrates the config format and backfills the new `app:` field into existing tickets.

### Added

- **Terminal ticket folders** — `tickets/shipped/`, `tickets/deferred/`, `tickets/wontfix/`. Created lazily on first use (no `.gitkeep`); ticket files move into them via `git mv` so rename history is preserved. Keeps the active set at `tickets/` root clean.
- **`/ticket-defer`** — park an active ticket in `tickets/deferred/` with a required reason. Reason can be given in any language; the command translates to English before writing.
- **`/ticket-close`** — close as wontfix (duplicate, invalid, obsolete, rejected) → `tickets/wontfix/`. Same translated-reason handling as defer.
- **`/ticket-reopen`** — bring a terminal ticket back to active. Useful when a shipped change regresses, a deferred ticket's moment arrives, or a closed ticket turns out to be real. Preserves the historical `## Shipped` / `## Deferred` / `## Closed` sections so the full lifecycle stays readable.
- **`/ticket-preview`** — build a ticket's feature branch and launch it locally (or push to staging, or deploy to a simulator) **without** merging to main. Separates "inspectable" from "shipped" so smoke-testing no longer requires a production deploy.
- **`/ticket-batch`** — run investigate + auto-approve + implement on multiple tickets in parallel, each in its own `git worktree` under `.worktrees/ticket-{id}/`. Spawns one subagent per ticket so each gets a fresh context window. Auto-approves by default; `Regression Risk: high` is a hard manual gate. Pre- and post-implement file-overlap conflict detection. Rollup preview (merge all branches into one scratch branch, preview once) or individual-per-ticket. Sends a single push notification (via whatever channel is set up in `CLAUDE.md`) when the whole batch is ready.
- **`/ticket-cleanup`** — reaper for worktrees and preview processes. Three forms: `{ID}` (targeted), `--all` (nuclear), no-arg (stale only). Idempotent. Also runs as a silent preflight inside `/ticket-list`, `/ticket-status`, and `/ticket-batch` so the system self-heals without explicit cleanup runs.
- **Preview profiles** — `.claude/ticket-config.md` now has a `## Preview profiles` section supporting **atomic** profiles (one command launches one thing, with port offset, readiness rule, sequential flag, dependencies) and **compound** profiles (ordered list of atomics launched together in dependency order). Compound previews are how a client + server run together, or a macOS host app runs alongside its iOS companion for end-to-end testing. Cross-component placeholders like `{SERVER_PORT}` are substituted after all component ports are computed. Multi-line `.preview.pid` records one row per component; teardown kills in reverse launch order.
- **Per-ticket `app:` field** — ticket frontmatter now names which preview profile the ticket targets. `/ticket-new` asks via AskUserQuestion if the project has 2+ profiles.
- **Deterministic per-ticket ports** — `{Preview port base} + {numeric-id} + {component offset}`. Same ticket always gets the same ports; parallel previews never collide up to 1000 tickets per component.
- **Automatic decruft on terminal transitions** — `/ticket-ship`, `/ticket-defer`, `/ticket-close` all kill the ticket's preview components and remove its worktree as a final phase. If a rollup preview is live, it's **rebuilt** excluding the removed ticket (or killed if no `review`-status tickets remain in the batch).
- **Multi-scheme Xcode detection in `/ticket-install`** — detects macOS + iOS schemes in the same project and proposes atomic profiles for each plus a `pair` compound. Also detects client+server monorepos (`dev:api` + `dev:web` scripts, or `apps/api/` + `apps/web/` subdirs), Docker Compose, and Vercel/Netlify projects.
- **Update-mode migration in `/ticket-install`** — existing installs are migrated to the profile format: flat `Preview:` → atomic profile named `default`, `app:` field added to `TEMPLATE.md`, `app:` backfilled into existing active + deferred tickets, `.worktrees/` added to `.gitignore`. All idempotent.

### Changed

- **`/ticket-new` ID allocation scans recursively** through `tickets/**/{PREFIX}*.md` including terminal subfolders. Previously it scanned only the root, which would have reused IDs the moment any ticket was archived into a subfolder. This closes the duplication vector before the new terminal folders existed.
- **`/ticket-list` defaults to active-only**; pass `--all` to include shipped/deferred/wontfix tables. The three terminal groups never appear in the default view so the list stays bounded as projects accumulate history.
- **`/ticket-ship` archives the ticket** into `tickets/shipped/` via `git mv` (not `cp`) as a new Phase 6, commits the move, and pushes. New Phase 7 tears down the ticket's worktree + preview processes.
- **All ID-consuming commands** (`investigate`, `approve`, `review`, `ship`, `delegate`, `collect`) now locate the ticket file in the active set and refuse to operate on terminal tickets, directing the user to `/ticket-reopen` first.
- **`.claude/ticket-config.md` format** — the old flat `Preview:` field is replaced by a `## Preview profiles` section. Migration is automatic via `/ticket-install` update mode.

### Fixed

- **Ticket ID duplication vector** — before this release, moving a ticket file out of `tickets/` root (even manually) would cause the next `/ticket-new` to reuse the missing ID. Now impossible by construction: ID scans are recursive, terminal moves use `git mv`, and tickets can't be deleted through any supported command.

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
