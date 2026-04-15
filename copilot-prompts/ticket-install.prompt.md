---
mode: agent
description: Install or update the ticket workflow in this project
argument-hint: ''
---

# Install the Ticket Workflow Into This Project

Bootstrap a project (new or existing) to use the universal ticket workflow. Creates the per-project scaffolding the ticket commands need: a tickets directory, a template, and a `.claude/ticket-config.md` with project-specific build/test/deploy commands and key source paths.

## Phase 1: Detect current state

1. Check if `.claude/ticket-config.md` already exists.
   - **If YES:** switch to **update mode**. Read the existing config and determine what's missing:
     - `## Preview profiles` section (new profile-based format)
     - `app:` field in `tickets/TEMPLATE.md`
     - `Main branch:` field in `.claude/ticket-config.md`
     - `## Automated Checks` section in `tickets/TEMPLATE.md`
   - Report what's missing and offer to migrate. Ask with options: "migrate to the new profile-based preview config", "re-detect the full stack", "edit specific fields", "stop".
   - **Migration rule (preview):** if the old config has a flat `Preview:` command, wrap it into a single atomic profile named `default`. Never silently discard user-written commands.
   - **Migration rule (main branch):** if `Main branch:` is absent, add it. Default to `main`.
   - **Migration rule (template):** if `tickets/TEMPLATE.md` lacks `## Automated Checks`, insert it between `## Test Report` and `## Verification Checklist (for human)`.
   - **If NO:** continue to Phase 2 (fresh install).

2. Check if `tickets/` already exists. If yes, note it will be reused (don't overwrite tickets).

3. Check if `CLAUDE.md` exists at the project root.

4. **Verify the primary branch is `main`:**
   - If git repo with remote: `git symbolic-ref refs/remotes/origin/HEAD`.
   - If git repo without remote: check `git branch`.
   - If the result is `master` (or not `main`):
     - Warn the user.
     - Ask: "Rename default branch to `main`?" with options: "yes, rename to main", "no, keep {branch}".
     - If yes: `git branch -m {branch} main`. If remote exists: push new branch, delete old (confirm first), update HEAD ref.
     - If no: proceed, record the actual branch name in ticket-config's `Main branch:` field.
   - If not a git repo: skip this check.

## Phase 2: Detect the stack

Look at files in the project root to identify the stack. Use file reads and glob searches — do NOT guess.

| Marker | Stack | Default commands |
|---|---|---|
| `package.json` | Node / npm | Read `scripts` from package.json — use `test`, `build`, `deploy` if present |
| `pnpm-lock.yaml` / `yarn.lock` | pnpm / yarn | Same but with `pnpm`/`yarn` |
| `Cargo.toml` | Rust | `cargo test`, `cargo build --release` |
| `go.mod` | Go | `go test ./...`, `go build ./...` |
| `*.xcodeproj` / `project.yml` / `Package.swift` | Swift / Xcode | `xcodebuild test ...`, `xcodebuild build ...` |
| `pyproject.toml` | Python (modern) | `pytest`, `python -m build` if applicable |
| `requirements.txt` | Python (legacy) | `pytest`, no build |
| `Gemfile` | Ruby | `bundle exec rspec` or `rake test` |
| `pom.xml` / `build.gradle*` | Java | `mvn test` / `gradle test` |
| `Makefile` (no other markers) | Generic | `make test`, `make build`, `make deploy` |

Multi-stack projects: pick the primary stack from the repo root; note secondary in "Key source locations."

For Xcode: run `xcodebuild -list` to enumerate schemes. Always confirm via user question.

## Phase 3: Discover key paths

- List top-level directories (skip `node_modules`, `.git`, `build`, `dist`, `.claude`, `tickets`).
- Look for `docs/`, `README.md`, `ARCHITECTURE.md` — these become "Context docs."
- Look for test directories.

## Phase 3b: Detect preview profiles

"Preview" means: build the feature branch and make it inspectable without shipping to prod. Profiles come in two flavors:

- **Atomic** — one command that launches one thing.
- **Compound** — a list of atomic profiles launched together in dependency order.

### Detection patterns

| Signal | Proposed profile(s) |
|---|---|
| Single `package.json` with a `dev` script | One atomic profile `default`: `npm run dev -- --port {PORT}` |
| `package.json` with both `dev:api`/`dev:server` AND `dev:web`/`dev:client` | Two atomic profiles + compound `fullstack` (default) |
| Monorepo with separate `apps/api/` + `apps/web/` | Same: `server`, `client`, compound `fullstack` |
| `docker-compose.yml` | One atomic profile `default`: `docker-compose up` |
| Vercel/Netlify config | One atomic profile `preview`: `git push preview {BRANCH}` |
| Single Xcode scheme | One atomic profile matching platform |
| Multiple Xcode schemes (run `xcodebuild -list`) | One atomic per platform + compound `pair` if both macOS+iOS present |
| CLI tool | One atomic profile with install command + prowl note |
| Library with no runtime | No profiles — tickets will use `app: (none)` |

### Atomic profile fields

- **Command** — shell command to launch. Supports placeholders: `{PORT}`, `{ID}`, `{BRANCH}`, `{WORKTREE}`, `{<OTHER>_PORT}`.
- **Port offset** — added to ticket numeric ID + port base. Default: 0 for first profile, +1000 per subsequent.
- **Ready when** — `http {PATH}`, `log {PATTERN}`, `delay {SECONDS}`, or `command-exit`.
- **Sequential** — `true` if only one instance can run at a time (iOS simulator). Default `false`.
- **Depends on** — list of other profiles that must be ready first.

### Compound profile fields

- **Components** — ordered list of atomic profile names.
- **Default** — `true` if this is the profile new tickets default to.

### Preview mode (per-project)

- `auto` — try rollup first; fall back to individual on merge conflict.
- `rollup` — always combine all tickets into one preview.
- `individual` — always one preview per ticket. Default if any profile is `Sequential: true`.

## Phase 4: Confirm with the user

Ask (in one batch) about:
- Test command (offer detected default + "other" + "none")
- Build command (same)
- Deploy command (same — "none" is valid)
- **Preview profiles** — show proposed profiles (atomic + compound) and confirm Command, Port offset, Ready-when, Sequential, Depends-on for each. Give the user a chance to rename, remove, or add profiles.
- **Preview mode** (`auto` / `rollup` / `individual`)
- Whether to proceed with detected key source locations or edit them

Do NOT proceed without confirmation. Detection isn't always right.

## Phase 4b: Update-mode migration (only if entering via Phase 1 YES branch)

Perform these migrations before writing scaffolding. Each is idempotent.

1. **Config: flat `Preview:` → profile.** Convert flat command to a `default` atomic profile. Remove the old flat field.
2. **Config: missing preview settings.** Add `Preview mode` and `Preview port base` if absent.
3. **TEMPLATE.md: add `app:` field.** Insert between `priority:` and `branch:` if missing.
4. **Existing ticket files: backfill `app:` field.** Walk all active and deferred tickets; insert `app:` with the default profile if missing. Skip shipped/closed tickets.
5. **`.gitignore`: ensure `.worktrees/`.** Add if missing.

Report each migration that ran.

## Phase 5: Write the scaffolding

1. **Create `tickets/TEMPLATE.md`** (only if it doesn't already exist — never overwrite):

```markdown
---
id: TKT-XXX
title: ""
type: bug | feature | enhancement
status: open
priority: low | medium | high | critical
app: {default-profile-name or (none) if project has no profiles}
branch: ""
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

## Description

## Reproduction Steps (bugs only)

## Acceptance Criteria
- [ ] 

---

## Investigation

## Proposed Solution

## Implementation Plan
- [ ] 

## Files Changed

## Test Report

## Automated Checks

## Verification Checklist (for human)
- [ ] 

## Regression Report
```

2. **Create `tickets/.gitkeep`** if no tickets exist yet.

3. **Ensure `.worktrees/` is in `.gitignore`.** Add if missing; preserve existing content.

4. **Create `.claude/ticket-config.md`** with confirmed values:

```markdown
# Ticket Workflow Config

- Stack: {detected stack}
- Tickets directory: tickets/
- ID prefix: TKT-
- Main branch: main

## Commands
- Test: {test command, or (none)}
- Build: {build command, or (none)}
- Deploy: {deploy command, or (none)}
- Lint: {lint command, or (none)}

## Preview settings
- Preview mode: {auto | rollup | individual}
- Preview port base: 3000

## Preview profiles

### {profile-name}  ({atomic|compound}){, default if default}
- Command: {command}
- Port offset: {N}
- Ready when: {rule}
- Sequential: {true|false}
- Depends on: [{other profile}, ...]

### {compound-name}  (compound, default)
- Components: [{atomic1}, {atomic2}]

## Key source locations
- {path} — {description}

## Context docs
- {path}
```

5. **Update `CLAUDE.md`** at the project root:
   - If exists: append a `## Tickets` section (only if absent).
   - If not: create it with just the `## Tickets` section.

   Section content:
   ```markdown
   ## Tickets

   This project uses the universal ticket workflow.

   - Tickets live in `tickets/` as `TKT-NNN.md`
   - Project-specific commands and source paths are in `.claude/ticket-config.md`
   - Common commands: `/ticket-new`, `/ticket-list`, `/ticket-investigate`, `/ticket-approve`, `/ticket-review`, `/ticket-ship`
   ```

## Phase 6: Smoke-test instructions

Output:
```
Ticket workflow installed in {project name}

Created:
- tickets/TEMPLATE.md
- .claude/ticket-config.md
- CLAUDE.md (created or updated with ## Tickets section)

Stack detected: {stack}
Test:   {test cmd}
Build:  {build cmd}
Deploy: {deploy cmd}

Verify with:
  /ticket-new "verify install"
  /ticket-list
```

## Rules

- NEVER overwrite an existing `tickets/TEMPLATE.md` or existing tickets.
- NEVER overwrite an existing `.claude/ticket-config.md` without user confirmation.
- NEVER overwrite `CLAUDE.md` — only append the `## Tickets` section if absent.
- Always confirm detected commands before writing the config. Auto-detection is a starting point.
- If the project isn't a git repo, warn the user but proceed.
- If no stack can be detected, ask the user to type commands manually.

## Compatibility Notes

- All source behaviors preserved exactly. Interactive confirmation questions use standard Copilot conversational prompts rather than a dedicated `AskUserQuestion` tool call, but the behavior is equivalent.
