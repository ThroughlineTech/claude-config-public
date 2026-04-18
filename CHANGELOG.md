# Changelog

All notable changes to `claude-config`. Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [0.2.13] — 2026-04-17

### Changed

- **`/ticket-promote` — prefix matching + auto-epic promotion.** Two enhancements driven by a dogfood test where the user has `TKT-102a` through `TKT-102f` plus `EPIC-voice-ux` all in `{tickets-dir}/stub/` and wants to promote the whole batch with a single call:
  - **Bare-number prefix match.** `/ticket-promote 102` now resolves to `TKT-102.md` plus any letter-suffix variants (`TKT-102a.md`, `TKT-102b.md`, `TKT-102f.md`, ...) — but not other numeric variants like `TKT-1020.md`. Fully-qualified IDs (e.g., `TKT-102a`) still match exactly.
  - **Referenced epics are auto-promoted.** For every ticket being moved, `/ticket-promote` reads its `epic:` frontmatter field and pulls the referenced `EPIC-<slug>.md` file from `stub/` to the active set alongside (flipping status to `open`). Each epic is moved once per call even if referenced by multiple tickets. `--all` now includes every `EPIC-*.md` in `stub/` (reversing the 0.2.11 exemption). This fixes an inconsistency from 0.2.11: `/ticket-investigate` looks for the epic file in the same directory as the ticket, but the previous rule left epics behind in `stub/` after their tickets were promoted — breaking the lookup.
  - **Failure mode softened.** Files that can't be promoted (wrong status, already in active, etc.) are now **skipped with a notice** rather than erroring the whole call. The command only errors outright if the overall call resolves to zero files.
- **`brainstorm-mode.md`** (and regenerated Copilot mirror) — the "Epics are file-naming-only for now" section is renamed to "Epics are lightly integrated — by design" and rewritten to describe the actual integration: `/ti` reads the north star, `/ticket-promote` moves epics with their tickets, nothing else integrates. The deliberate limitation (no `/tl` listing, no auto-ship tracking) is preserved; the Plane migration rationale is unchanged.

## [0.2.12] — 2026-04-17

### Changed

- **`/ticket-investigate` — epic awareness and `status: stub` acceptance.** Second pass on the command. Extends the plan-mode discipline from 0.2.10 with:
  - **Epic framing.** When a ticket's frontmatter has an `epic:` field, `/ti` now reads **only** the parent epic's `## North star` section as read-only framing context. Firewalled: does NOT read sibling tickets, does NOT read a brainstorm transcript, does NOT expand `/ti`'s scope beyond the single ticket. If the epic file is missing, emit a warning and proceed as standalone. When an epic was read, the Investigation section leads with `Epic context: EPIC-<slug> — {one-line paraphrase}` so the user can verify the framing loaded.
  - **Same-directory epic lookup.** The epic file is located in the same directory as the ticket, whatever that directory is called — works for `{tickets-dir}/`, `stub/`, a legacy `proposed/`, or any other naming.
  - **`status: stub` is now a valid pre-flight state** (alongside `open`). The investigation itself promotes status to `proposed` at the end; no separate manual status flip needed before `/ti`. If a ticket is already `proposed` or later, `/ti` still stops (single-ticket) or re-reads the existing plan (multi-ticket) — unchanged from before.
  - **File-location logic unchanged.** `/ti` still searches `{tickets-dir}/{ID}.md` plus terminal subfolders; it does NOT reach into `stub/`. `/ticket-promote` remains the path from stub-dir to active-dir.
- **`copilot-prompts/ti.prompt.md`** — unchanged (thin delegate to the canonical prompt).

## [0.2.11] — 2026-04-17

### Added

- **`brainstorm-mode.md`** — new global discipline doc governing brainstorm sessions. Companion to `plan-mode.md`, parallel install pattern (repo-root file + `~/.claude/` symlink + generated Copilot mirror). Codifies capture-over-convergence, no-code-no-plans, running candidate-ticket list, split-proposals, external-feedback triage, and explicit user-signaled stop. Prevents the "one giant ticket instead of N small ones" failure mode.
- **`/brainstorm` slash command** (`commands/brainstorm.md` + `copilot-prompts/brainstorm.prompt.md`) — entry point for brainstorm mode. Optional topic arg, optional `--prowl`. On user stop-signal, scans all ticket dirs (active + `stub/` + terminal subdirs) for the next N sequential IDs, then writes an `EPIC-<slug>.md` + N `TKT-NNN.md` stubs to `{tickets-dir}/stub/`. Does NOT produce plans or code; does NOT auto-promote.
- **`/ticket-promote` slash command** (`commands/ticket-promote.md` + `copilot-prompts/ticket-promote.prompt.md`) — the human gate between brainstorm output and `/ti` input. Takes TKT-IDs (or `--all`) and, for each stub with `status: stub`, moves the file from `{tickets-dir}/stub/` to the active `{tickets-dir}/` and flips `status: stub → open`. EPIC files intentionally stay in `stub/` — they're documentation, not workflow objects.
- **New ticket status: `stub`**, and new subdirectory convention: `{tickets-dir}/stub/` (parallel to `shipped/`, `deferred/`, `wontfix/`). Existing commands (`/tl`, `/ts`, etc.) ignore the subdir automatically — no behavioral changes needed elsewhere.
- **`CLAUDE.md` Brainstorm Mode section** pointing to `brainstorm-mode.md`, paralleling the Plan Mode section.
- **`install.sh` and `preflight.sh` wiring** — `brainstorm-mode.md` is symlinked to `~/.claude/`, the Copilot mirror is auto-generated, and the VS Code user-prompts symlink loop picks up the new `.prompt.md` files. Preflight expects 22 repo files (was 19).

### Scope notes

- **Epics are file-naming-only for now.** `EPIC-<slug>.md` files document the north star + member tickets, but no existing command knows about epics (intentional; Plane migration coming, Plane has native epic support). Documented in `brainstorm-mode.md`.
- **Transcript capture is not implemented.** Agents can't reliably self-capture conversations, and a half-captured transcript that users trust is worse than none. Dropped from the original spec.
- **No short alias for `/ticket-promote`.** `/tp` is taken by `/ticket-preview`; deferred until usage patterns surface a clear winner.

## [0.2.10] — 2026-04-17

### Changed

- **`/ticket-investigate` now follows plan-mode discipline.** `commands/ticket-investigate.md` and `copilot-prompts/ticket-investigate.prompt.md` updated with: a new `## Plan Mode Discipline` section pointing to `~/.claude/plan-mode.md`; an Investigation Phase step that captures `investigated_at_sha` via `git rev-parse`; the plan format from `plan-mode.md` (paragraph + Relevant files + Steps + Verification + Out of scope + SHA footer) replacing the old bullet-list format; a new `Subtract Before Presenting` section (cut / defer / one-screen / file-ceiling / delight-vs-fix checks); and an updated Finish summary that names the plan size, Relevant files, SHA, and human ship gate. The multi-ticket ordering analysis (`--order-only`, `--in-given-order`, `--auto`) is unchanged.
- **`copilot-prompts/ti.prompt.md`** — unchanged (thin delegate to the canonical prompt).

## [0.2.9] — 2026-04-17

### Added

- **`plan-mode.md`** — new global doc capturing plan-mode discipline for any agent (Claude Code, Copilot, Gemini, GPT). Covers scope anchoring, plan-size budgets, subtraction passes, external-feedback triage, ExitPlanMode-rejection interpretation, rescope visibility, side-task isolation, file-growth flagging, human ship gates, and the canonical plan-file format. Distilled from a post-mortem on a voice-UX ticket that drifted from "port the POC" into a two-flag state-machine refactor.
- **`CLAUDE.md` pointer section** — a new `## Plan Mode` section directs agents to read `plan-mode.md` before presenting or editing a plan. Non-optional.
- **`install.sh` symlinks `plan-mode.md` → `~/.claude/plan-mode.md`** and generates `copilot-prompts/plan-mode.instructions.md` from it (same applyTo-frontmatter pattern used for `claude-global.instructions.md`). Verification check at the bottom of install.sh confirms the symlink.
- **`copilot-prompts/plan-mode.instructions.md`** — generated Copilot mirror with `applyTo: "**"`, picked up by the existing VS Code user-prompts symlink loop on install.

### Changed

- **Existing installs**: re-run `bash install.sh` to pick up the new symlink, the Copilot mirror, and the VS Code wiring. No manual steps required.

## [0.2.8] — 2026-04-15

### Added

- **Full Copilot prompt suite** — all 17 core ticket workflow commands (`ticket-new` through `ticket-install`) are now synced to `copilot-prompts/` as `ticket-*.prompt.md` files, using the three-bucket compatibility model (Preserved / Adapted / Unsupported). Alias short-forms (`tn`, `tch`, `tsh`, etc.) are also present as thin delegates that reference the full prompt. All files are symlinked into VS Code's user prompts directory on install, making the full ticket workflow available in Copilot Chat.
- **`sync-claude-command` Copilot prompt** (`copilot-prompts/sync-claude-command.prompt.md`) — migration agent that keeps Copilot prompts aligned with Claude command definitions. Accepts a single source file or `--all` to refresh all non-alias commands in one pass. Alias files are excluded automatically (they're thin delegates; the canonical prompt changing doesn't require the alias to change). Supports `--dry-run` for preview-without-write.
- **`install.sh` now symlinks all of `copilot-prompts/`** — the VS Code Copilot wiring section now loops over all `*.md` files in `copilot-prompts/` instead of hardcoding two specific files. New prompts added to `copilot-prompts/` are picked up automatically on the next `bash install.sh` run.

### Changed

- **`docs/04-architecture.md`** — Layer 1 and Layer 2 diagrams updated to reflect the full `copilot-prompts/` suite; component table includes `sync-claude-command.prompt.md` and the ticket prompt files.
- **`docs/01-install.md`** — step 7 updated to describe the per-file loop rather than two hardcoded symlinks.
- **`docs/11-maintenance.md`** — "When you edit a command" now includes instructions for running `sync-claude-command` (or `--all`) and committing the updated Copilot prompt in the same commit.

## [0.2.7] — 2026-04-14

### Added

- **MQTT intercom promotion** — the five slash commands (`/register`, `/send`, `/draft`, `/machines`, `/repos`) and six dispatcher helpers (`send-job`, `intercom-session`, `intercom-machines`, `intercom-repos`, `intercom-inbox-mutate`, `intercom-inbox-listener`) from the `mqtt-pivot` branch of [claude-intercom](https://github.com/danrichardson/claude-intercom) are now committed directly in this repo under `bin/`. `install.sh` symlinks them into `~/bin/` via the existing `link()` helper on every platform.
- **UserPromptSubmit hook** — `hooks/surface-intercom-replies.sh` is installed to `~/.claude/hooks/` and registered in `settings.base.json` so unread inbox replies surface at the top of every Claude Code response. The hook exits cleanly when the inbox file doesn't exist (safe on non-dispatcher machines).
- **Task Scheduler auto-registration (Windows)** — `windows/intercom-inbox-listener.xml.template` (with `{{WINDOWS_USER}}` placeholder) is rendered at install time to `windows/intercom-inbox-listener.xml.rendered` (gitignored) and registered via `schtasks /Create /XML ... /TN intercom-inbox-listener /F`. Idempotent: re-running install re-registers with `/F`.
- **Creds-file prompt** — `install.sh` prompts for `MQTT_HOST`, `MQTT_PORT`, `MQTT_USER`, `MQTT_PASS` and writes `~/.config/intercom/creds` (chmod 600) if the file is absent. Skipped in non-interactive mode.
- **`Bash(mosquitto_pub:*)` and `Bash(mosquitto_sub:*)`** added to base permissions; **`Bash(schtasks:*)`** added to Windows permissions.

### Removed (supersedes 0.2.6)

- **HTTP-era scaffolding removed** — `mcp/intercom.mcp.json.template`, `launchd/com.intercom.worker.plist.template`, `systemd/intercom-worker.service.template`, `secrets/.env.example` are deleted. The TKT-001 intercom block in `install.sh` (clone/bun/MCP/daemon wiring) is replaced by the MQTT-era block. `commands/list-messages.md` and `commands/get-message.md` are removed (replies surface via hook now).
- **PII fix applied** — the four helpers that hardcoded `/c/Users/fubar/AppData/Local/Microsoft/WinGet/Links` now use `${LOCALAPPDATA}/Microsoft/WinGet/Links` (portable across any Windows username; Git Bash sets `$LOCALAPPDATA` automatically).

## [0.2.6] — 2026-04-14

### Added

- **Intercom one-shot bootstrap** — `install.sh` now clones [claude-intercom](https://github.com/danrichardson/claude-intercom) at a pinned tag (`INTERCOM_TAG`, default `pre-claude-config-merge`) into `$INTERCOM_PATH` (default `~/src/claude-intercom`), runs `bun install`, and renders `mcp/intercom.mcp.json.template` to a user-level `~/.claude/.mcp.json` (project-local available on prompt). Prompts for `INTERCOM_SECRET`/`BROKER_HOST`/`CLIENT_ROLE`/`PROWL_KEY`, offers to persist to `secrets/.env` (gitignored, chmod 600). On macOS offers to install the worker daemon via launchd (default yes); on Linux via systemd --user (default no); skipped on Windows. Idempotent: re-running is a clean no-op when the pin, lockfile, and rendered configs haven't changed. Guarded by `command -v bun && command -v git` — machines without bun get a clean skip message. Templates live in [mcp/](../mcp/), [launchd/](../launchd/), [systemd/](../systemd/); runbook at [docs/intercom-runbook.md](../docs/intercom-runbook.md).
- **`Bash(bun:*)`** added to base permissions; **`Bash(launchctl:*)`** and **`Bash(systemctl:*)`** added to Mac permissions.

## [0.2.5] — 2026-04-14

### Added

- **Intercom slash commands** — `/register`, `/send`, `/draft`, `/list-messages`, `/get-message`, `/machines`, `/repos` wrap the Claude Intercom MCP server. Lets a Claude Code session delegate work to another machine over a Tailnet broker: `/register mac-mini ~/src/foo` sets the target, `/send "run tests"` dispatches, responses land in the inbox. `/draft` composes a structured prompt and asks for approval before dispatch. See [commands/README.md](../commands/README.md#intercom-commands-cross-machine-messaging).
- **`--prowl` universal opt-in flag** — any slash command or freeform request can append `--prowl` to get an end-of-task Prowl notification, regardless of whether that command prowls by default. Commands that already prowl (`/tch`, `/tb`, `/tp`, `/ticket-collect`) treat it as a no-op. Documented in [CLAUDE.md](../CLAUDE.md) under Universal Conventions.

## [0.2.4] — 2026-04-13

### Added

- **Automated verification in review checklists** — `/ticket-chain` and `/ticket-review` now run automated checks (tests, typecheck, build, lint, rebase status, merge conflict detection) before generating the human checklist. Results are stamped pass/fail in a new `### Automated Checks` section per ticket, so the human reviewer only needs to verify what requires eyes and hands. Failing checks are shown with strikethrough and error details; the Verdict section summarizes the automated result.
- **Branch enforcement at install time** — `/ticket-install` now checks if the repo's default branch is `main`. If it's `master` (or anything else), warns and offers to rename. The detected branch is recorded as `Main branch:` in `.claude/ticket-config.md`.
- **`Main branch` config field** — `.claude/ticket-config.md` now stores the project's main branch name. All branch-detecting commands (`/ticket-approve`, `/ticket-ship`, `/ticket-chain`) read this field first, falling back to `git symbolic-ref` only if absent. If the detected branch is `master`, commands warn and suggest running `/ticket-install` to migrate.

### Changed

- **`/ticket-review` Phase 2 rewritten** — now runs the full automated check suite (tests, build, lint, typecheck, rebase status) and integrates results directly into the checklist as `### Automated Checks`, replacing the old separate `Tests: passing` / `Build: clean` lines in the finish output.
- **`/ticket-chain` Phase 4 gains Step B** — automated verification runs between preview deploy (Step A) and checklist generation (now Step C). Step D is the commit.
- **Branch detection standardized** — `/ticket-approve`, `/ticket-ship`, and `/ticket-chain` all use the same pattern: read `Main branch` from config, fall back to `git symbolic-ref`, warn on `master`.

## [0.2.3] — 2026-04-09

### Changed

- **Interactive review checklist verdicts** — review checklists now use `- [ ] pass` / `- [ ] fail — reason:` checkboxes instead of a summary table with `☐` characters. Checkboxes are clickable in VS Code markdown preview and GitHub. Each ticket gets an inline verdict section after its verification steps, plus a consolidated Results section at the bottom for at-a-glance scanning. Failure reasons are recorded inline on the fail checkbox line. Applies to `/ticket-chain`, `/ticket-review`, `/ticket-collect`, and delegation briefs.

## [0.2.2] — 2026-04-09

### Added

- **`/ticket-chain` with smart dependency detection and wave execution** — the "queue up work and walk away" command. Investigates all tickets in parallel, detects inter-ticket dependencies (both explicitly declared by investigators and inferred from file-overlap heuristics with hub-file threshold), builds a DAG, resolves cycles using user argument order as tiebreaker, computes execution waves, implements independent tickets in parallel worktrees within each wave, re-investigates dependent tickets against the updated codebase before starting the next wave. **Defaults to review, not ship:** after implementation, deploys to preview/staging and generates a consolidated `CHAIN-REVIEW-*.md` checklist for human verification. Prowls when ready. User ships explicitly with `/tch --ship` or `/tsh` per ticket. Flags: `--dry-run` (investigate + show wave plan), `--sequential` (strict one-at-a-time), `--ship` (auto-ship, fire-and-forget). Alias: `/tch`.
- **Full-lifecycle delegation with batch support** — `/ticket-delegate {ID}` (no phase argument) delegates the entire lifecycle — investigate, implement, commit — to the target model in one brief. Pass multiple IDs (`/ticket-delegate 10 11 12 13`) for batch delegation: asks parallel vs. sequential, creates worktrees for parallel mode, generates an instruction file with the run order. On `/ticket-collect` (also supports multiple IDs), Claude acts as code reviewer: reads the investigation, reviews the diff, checks tests, and writes a `## Delegation Review` with verdict (`approved` / `concerns` / `rejected`). Batch collect generates a consolidated review checklist. New brief template: `brief-templates/full.md`. Phase-specific delegation (`/ticket-delegate {ID} investigate`, etc.) still works for surgical single-ticket cases.
- **Bare-number ID shorthand** — all ticket commands now accept bare numbers (e.g., `/tch 1 2 3 4 6`, `/ti 14`, `/td 3 too risky`). Numbers are resolved to full ticket IDs by reading the prefix from `ticket-config.md` and zero-padding to match existing files.

### Fixed

- **`/ticket-batch` worktree sync-back** — after Phase 4 subagents complete, ticket files that reached `proposed` or `review` status are now copied from `.worktrees/ticket-{id}/tickets/{ID}.md` back to `tickets/{ID}.md` in the main working directory, staged, and committed. Previously the main branch copies remained stale after a batch investigation because subagents only wrote to their worktree copies.

## [0.2.1] — 2026-04-08

### Added

- **Command frontmatter** — every `/ticket-*` command has `description` and `argument-hint` fields so the slash-command picker shows what the command does and the expected arguments inline, instead of just the bare name.
- **Short aliases** — `commands/aliases.map` defines single-letter/short aliases (`/tn`, `/tl`, `/ts`, `/ti`, `/ta`, `/tr`, `/tp`, `/tb`, `/tsh`, `/td`, `/tc`, `/tro`, `/tcl`). `install.sh` reads the map and generates gitignored real `.md` wrapper files in `commands/` on each machine (each wrapper delegates to its canonical command via `$ARGUMENTS`), so aliases propagate with a `git pull + bash install.sh` and don't pollute the repo. Real files rather than symlinks because the Claude Code harness dedupes symlinked commands to a single entry, hiding either the alias or the canonical. Stale aliases removed from the map are reaped on the next install.

## [0.2.0] — 2026-04-08

Major expansion of the ticket workflow: terminal-state management, preview-before-ship, and parallel batch mode. Existing projects can upgrade via `/ticket-install` in update mode — it migrates the config format and backfills the new `app:` field into existing tickets.

### Added

- **Terminal ticket folders** — `tickets/shipped/`, `tickets/deferred/`, `tickets/wontfix/`. Created lazily on first use (no `.gitkeep`); ticket files move into them via `git mv` so rename history is preserved. Keeps the active set at `tickets/` root clean.
- **`/ticket-defer`** — park an active ticket in `tickets/deferred/` with a required reason. Reason can be given in any language (e.g. Danish); the command translates to English before writing.
- **`/ticket-close`** — close as wontfix (duplicate, invalid, obsolete, rejected) → `tickets/wontfix/`. Same translated-reason handling as defer.
- **`/ticket-reopen`** — bring a terminal ticket back to active. Useful when a shipped change regresses, a deferred ticket's moment arrives, or a closed ticket turns out to be real. Preserves the historical `## Shipped` / `## Deferred` / `## Closed` sections so the full lifecycle stays readable.
- **`/ticket-preview`** — build a ticket's feature branch and launch it locally (or push to staging, or deploy to a simulator) **without** merging to main. Separates "inspectable" from "shipped" so smoke-testing no longer requires a production deploy.
- **`/ticket-batch`** — run investigate + auto-approve + implement on multiple tickets in parallel, each in its own `git worktree` under `.worktrees/ticket-{id}/`. Spawns one subagent per ticket so each gets a fresh context window. Auto-approves by default; `Regression Risk: high` is a hard manual gate. Pre- and post-implement file-overlap conflict detection. Rollup preview (merge all branches into one scratch branch, preview once) or individual-per-ticket. One prowl when the whole batch is ready.
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
- **Prowl API key in CLAUDE.md** means the repo must be private. Splitting secrets into a gitignored `~/.claude/secrets.md` is documented in `docs/09-faq.md` as an option for users who want to make the workflow public.

## Release notes format

When adding entries in the future, use these categories as needed:

- **Added** — new features
- **Changed** — changes to existing features
- **Deprecated** — features that still work but will be removed later
- **Removed** — features removed
- **Fixed** — bug fixes
- **Security** — anything related to credentials, permissions, or deny lists
