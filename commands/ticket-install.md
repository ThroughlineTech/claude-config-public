---
description: 'install or update the ticket workflow in this project'
---

# Install the Ticket Workflow Into This Project

You are bootstrapping a project (new or existing) to use the universal ticket workflow. The slash commands themselves live at `~/.claude/commands/ticket-*.md` and are inherited by every project automatically. This command creates the per-project scaffolding the universal commands need: a tickets directory, a template, and a `.claude/ticket-config.md` that records project-specific build/test/deploy commands and key source paths.

## Phase 1: Detect current state

1. Check if `.claude/ticket-config.md` already exists.
   - If YES: switch to **update mode**. Read the existing config and determine what's missing:
     - Preview settings (old installs have none, or only a flat `Preview:` field)
     - `## Preview profiles` section (the new profile-based format)
     - `app:` field in `tickets/TEMPLATE.md`
     - `Main branch:` field in `.claude/ticket-config.md` (added in 0.2.4)
     - `## Automated Checks` section in `tickets/TEMPLATE.md` (added in 0.2.4)
   - Tell the user what's missing and offer to migrate. Use AskUserQuestion with options: "migrate to the new profile-based preview config", "re-detect the full stack", "edit specific fields", "stop".
   - **Migration rule (preview):** if the old config has a single flat `Preview:` command, wrap it into a single atomic profile named `default` in the new `## Preview profiles` section and remove the old flat field. Never silently discard user-written commands.
   - **Migration rule (main branch):** if `Main branch:` is absent, add it after `ID prefix:` using the result of the branch check in step 4. Default to `main`.
   - **Migration rule (template):** if `tickets/TEMPLATE.md` exists but lacks `## Automated Checks`, insert it between `## Test Report` and `## Verification Checklist (for human)`.
   - If NO: continue to Phase 2 (fresh install).
2. Check if `tickets/` already exists. If yes, note that it'll be reused (don't overwrite tickets).
3. Check if `CLAUDE.md` exists at the project root.
4. **Verify the primary branch is `main`.**
   - If the project is a git repo with a remote: `git symbolic-ref refs/remotes/origin/HEAD` → extract the branch name.
   - If the project is a git repo without a remote: check `git branch` for the current/default branch.
   - If the result is `master` (or anything other than `main`):
     a. Warn the user: "This repo's default branch is `{branch}`, not `main`."
     b. Use AskUserQuestion: "Rename default branch to `main`?" with options: "yes, rename to main", "no, keep {branch}".
     c. If yes:
        - `git branch -m {branch} main`
        - If remote exists: `git push origin main`, then `git push origin --delete {branch}` (confirm with user first), then `git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main`
     d. If no: proceed, but record the actual branch name in ticket-config's `Main branch:` field.
   - If the result is already `main`: no action needed.
   - If not a git repo: skip this check.

## Phase 2: Detect the stack

Look at files in the project root and key subdirectories to identify the stack. Use Glob and Read tools — do NOT guess. Possible signals:

| Marker file(s)                                | Stack                | Default commands                                                                 |
|-----------------------------------------------|----------------------|----------------------------------------------------------------------------------|
| `package.json`                                | Node / npm           | Read `scripts` from package.json — use `test`, `build`, `deploy` if present      |
| `pnpm-lock.yaml` / `yarn.lock`                | pnpm / yarn          | Same as above but `pnpm`/`yarn` instead of `npm`                                 |
| `Cargo.toml`                                  | Rust                 | `cargo test`, `cargo build --release`                                            |
| `go.mod`                                      | Go                   | `go test ./...`, `go build ./...`                                                |
| `*.xcodeproj` / `project.yml` / `Package.swift` | Swift / Xcode      | `xcodebuild test -project X -scheme S -destination 'platform=macOS'`, `xcodebuild build ...` |
| `pyproject.toml`                              | Python (modern)      | `pytest` (or read from pyproject), `python -m build` if applicable               |
| `requirements.txt`                            | Python (legacy)      | `pytest`, no build                                                                |
| `Gemfile`                                     | Ruby                 | `bundle exec rspec` or `rake test`                                               |
| `pom.xml` / `build.gradle*`                   | Java                 | `mvn test` / `gradle test`                                                       |
| `Makefile` (no other markers)                 | Generic              | `make test`, `make build`, `make deploy`                                         |

Multi-stack projects (e.g. a Rust backend + Vite frontend) are common — pick the *primary* stack based on what's at the repo root, and note the secondary in "Key source locations."

For Xcode projects specifically:
- Run `xcodebuild -list -project {found-project}` (or `-workspace`) to enumerate schemes. Pick a sensible default but ALWAYS confirm via AskUserQuestion.
- Look in `scripts/` for a release/deploy script (e.g. `build-release.sh`) and propose it as the Deploy command.

## Phase 3: Discover key paths

- List top-level directories (Glob `*/`) and identify likely source dirs (skip `node_modules`, `.git`, `build`, `dist`, `.claude`, `tickets`).
- Look for `docs/`, `README.md`, `ARCHITECTURE.md` — these become "Context docs."
- Look for test directories (`tests/`, `test/`, `*Tests/`, `__tests__/`).

## Phase 3b: Detect preview profiles

"Preview" means: build the ticket's feature branch and make it *inspectable* without shipping to prod. A project can have multiple **preview profiles** — named recipes like `macos`, `ios`, `server`, `client`, `fullstack` — and each ticket picks one via its `app` field. Profiles come in two flavors:

- **Atomic** — one command that launches one thing (e.g. `server` runs the API on port 3014).
- **Compound** — a list of atomic profiles launched together in dependency order (e.g. `fullstack = [server, client]`, or `pair = [macos, ios]`). Compound profiles are how you preview a client + server simultaneously, or how you run a macOS host app alongside its iOS companion for end-to-end testing.

### Detection patterns

Walk the repo and propose profiles based on what you find. Common patterns:

| Signal | Proposed profile(s) |
|---|---|
| Single `package.json` with a `dev` script | One atomic profile `default`: `npm run dev -- --port {PORT}` (swap `npm`→`pnpm`/`yarn` per lockfile). |
| `package.json` with **both** `dev:api`/`dev:server` AND `dev:web`/`dev:client` scripts | Two atomic profiles (`server`, `client`) **and** a compound `fullstack: [server, client]` marked as the default. The client's command includes `--api http://localhost:{SERVER_PORT}` so it finds the server. |
| Monorepo with separate `apps/api/` + `apps/web/` (or similar) each having their own `package.json` | Same as above: `server`, `client`, and compound `fullstack`. Each atomic profile `cd`s into its subdir first. |
| `docker-compose.yml` at root | One atomic profile `default`: `docker-compose up`. Simple, handles multi-service itself. |
| Vercel/Netlify config (`vercel.json`, `netlify.toml`) | One atomic profile `preview`: `git push preview {BRANCH}`, mode `rollup`. |
| `*.xcodeproj` / `*.xcworkspace` with **one** scheme | One atomic profile matching the platform (macOS: `open .app`; iOS: `xcrun simctl launch`). |
| `*.xcodeproj` / `*.xcworkspace` with **multiple** schemes for different platforms — run `xcodebuild -list` to enumerate | One atomic profile per platform-distinct scheme (e.g. `macos`, `ios`), **plus** a compound `pair: [macos, ios]` if both are present. The compound exists for tickets that affect shared code or require both apps running (Bonjour pairing, cross-device features, etc.). |
| Xcode project + a separate backend service in the same repo | Atomic profile for the app + atomic profile for the backend + compound that runs backend first, then app. |
| CLI tool (`bin/` in package.json, Rust binary in Cargo.toml) | One atomic profile with `npm link` / `cargo install --path .` and a prowl note to run the binary. |
| Library with no runtime | No profiles (leave section empty — tickets will just say `app: (none)`). |
| Nothing obvious | No profiles; prompt the user to define one later. |

### Atomic profile fields

Each atomic profile has:

- **Command** — the shell command to launch it. Uses placeholders (see below).
- **Port offset** — added to the ticket's numeric ID + port base to compute this profile's port. Defaults: first profile `0`, each subsequent atomic profile `1000` higher (so server=0, client=1000, third=2000, etc.). Reserve offset `999` per component for rollup previews.
- **Ready when** — how to know the process is live. Options: `http {PATH}` (poll a URL), `log {PATTERN}` (wait for a regex match in stdout), `delay {SECONDS}` (blind sleep, last resort), `command-exit` (wait for the command itself to exit, for build-and-install flows like Xcode). Default: `http /` for port-based, `command-exit` for build-and-install.
- **Sequential** — `true` means only one instance of this profile can run at a time on this machine (iOS simulator, anything that binds a system-singleton resource). Default `false`.
- **Depends on** — list of other profiles that must be ready before this one starts. Empty for standalone atomics.

### Compound profile fields

Each compound profile has:

- **Components** — ordered list of atomic profile names. Launch order follows dependencies; if no dependencies are declared, it's the list order.
- **Default** — `true` if this is the profile new tickets default to. Only one profile (atomic or compound) should be marked default.

### Placeholders

Available in any profile's command:

- `{PORT}` — this profile's computed port (`Preview port base + numeric-id + offset`)
- `{ID}` — ticket ID
- `{BRANCH}` — feature branch
- `{WORKTREE}` — absolute path to the ticket's worktree
- `{<OTHER_PROFILE>_PORT}` — port of another profile in the same compound (e.g. `{SERVER_PORT}`). Substituted after all components' ports are computed, so components can reference each other.

### Preview mode (still per-project)

- `auto` — `/ticket-batch` tries a merged rollup preview first; falls back to individual on merge conflict. Default for webapps.
- `rollup` — always combine all tickets into one preview (fail if any merge conflicts — no fallback).
- `individual` — always one preview per ticket. Default if *any* profile in the project is marked `Sequential: true` (e.g. iOS projects).

## Phase 4: Confirm with the user

Use **AskUserQuestion** to confirm the proposed config. Ask in one batch (multiple questions per AskUserQuestion call) about:
- Test command (offer the detected default + "other" + "none")
- Build command (same)
- Deploy command (same — "none" is a valid and common answer)
- **Preview profiles** — show the proposed profiles (atomic + any compound) and confirm each one's Command, Port offset, Ready-when, Sequential, and Depends-on. For compounds, confirm the Components list and which profile is the default. Give the user a chance to rename profiles, remove proposed ones, or add extras. If detection found nothing, ask whether to define a profile manually or skip (pure libraries can have no profiles).
- **Preview mode** (`auto` / `rollup` / `individual` — default `individual` if any profile is `Sequential: true`, else `auto`)
- Whether to proceed with the detected key source locations or edit them

Do NOT proceed without confirmation. Detection isn't always right.

## Phase 4b: Update-mode migration (only runs if we entered via Phase 1's YES branch)

If you're in update mode, before writing scaffolding in Phase 5, perform these migrations against the existing files. Each is idempotent — if the target state is already correct, skip it.

1. **Config: flat `Preview:` → profile.** If `.claude/ticket-config.md` has a flat `Preview:` command under `## Commands`:
   - Create a `## Preview profiles` section if missing.
   - Convert the flat command into a single atomic profile named `default` with `Port offset: 0`, `Ready when: http /`, `Sequential: false`, marked `default: true`.
   - Remove the `- Preview:` line from `## Commands`. Never silently discard the command — the whole point is to preserve it.
   - If the user then answers the Phase 4 AskUserQuestion with better-detected profiles (e.g. we just detected an Xcode multi-scheme layout), offer to **replace** `default` with the new profiles, but show both before overwriting.

2. **Config: missing preview settings.** If `Preview mode` or `Preview port base` lines don't exist under `## Preview settings`, add them with defaults (`auto` mode, base `3000`; `individual` if any profile is sequential).

3. **TEMPLATE.md: add `app:` field.** If `tickets/TEMPLATE.md` exists and its frontmatter doesn't have an `app:` line, insert it between `priority:` and `branch:`. Default value is the name of the project's default profile (or `(none)` if no profiles).

4. **Existing ticket files: backfill `app:` field.** Walk `{tickets-dir}/**/{PREFIX}*.md` (including terminal subfolders). For each ticket whose frontmatter lacks `app:`, insert it with the project's default profile as the value. This is a best-effort default — the user can edit individual tickets if they need a different profile. **Skip shipped/closed tickets from editing** (they're historical; leave them alone unless the user explicitly asks). Only backfill active and deferred tickets.

5. **`.gitignore`: ensure `.worktrees/`**. Same rule as fresh-install step 2b — add if missing, leave alone if present.

Report each migration that ran (or "(no changes needed)") so the user sees what was touched.

## Phase 5: Write the scaffolding

1. **Create `tickets/TEMPLATE.md`** with this exact content (only if it doesn't already exist — never overwrite):

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
<!-- What needs to happen? What's broken? What should exist that doesn't? -->


## Reproduction Steps (bugs only)
<!-- Step-by-step to reproduce the issue -->


## Acceptance Criteria
<!-- When is this done? Be specific. -->
- [ ] 


---
<!-- Everything below is filled by the agent. Do not edit manually. -->

## Investigation
<!-- Agent fills this during /ticket-investigate -->


## Proposed Solution
<!-- Agent fills this during /ticket-investigate -->


## Implementation Plan
<!-- Agent fills this during /ticket-investigate -->
- [ ] 


## Files Changed
<!-- Agent fills this during implementation -->


## Test Report
<!-- Agent fills this after implementation -->


## Automated Checks
<!-- Agent fills this during /ticket-review or /ticket-chain -->


## Verification Checklist (for human)
<!-- Agent fills this during /ticket-review -->
- [ ] 


## Regression Report
<!-- Agent fills this before merge -->

```

2. **Create `tickets/.gitkeep`** if no tickets exist yet (so the empty dir gets committed).

2b. **Ensure `.worktrees/` is in `.gitignore`.** This is where `/ticket-batch` creates per-ticket worktrees and where preview PID/meta files live — none of it should ever be committed.
   - If `.gitignore` doesn't exist, create it with `.worktrees/` as the only entry.
   - If `.gitignore` exists and doesn't contain a `.worktrees` entry, append `.worktrees/` on a new line (preserve existing content exactly — no reordering, no rewriting).
   - If it's already present (in any form: `.worktrees`, `.worktrees/`, `/.worktrees/`), leave it alone.

3. **Create `.claude/ticket-config.md`** with the confirmed values:

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
- Command: {command with {PORT}, {BRANCH}, {ID}, {WORKTREE}, {OTHER_PORT} placeholders}
- Port offset: {N}
- Ready when: {http /health | log "ready on port" | delay 5 | command-exit}
- Sequential: {true|false}
- Depends on: [{other profile}, ...]  (omit if none)

### {compound-name}  (compound, default)
- Components: [{atomic1}, {atomic2}]
- (compound profiles inherit dependency order from their components)

<!-- Repeat blocks per profile. Leave the whole ## Preview profiles section empty
     (no blocks) for projects with no preview story (pure libraries, etc.). -->


## Key source locations
- {path} — {one-line description}
- {path} — {one-line description}
...

## Context docs
- {path}
- {path}
```

4. **Update `CLAUDE.md`** at the project root:
   - If `CLAUDE.md` exists: append a `## Tickets` section (only if it doesn't already have one).
   - If `CLAUDE.md` does NOT exist: create it with just the `## Tickets` section.

   Section content:
   ```markdown
   ## Tickets

   This project uses the universal ticket workflow. Slash commands are inherited from `~/.claude/commands/ticket-*.md`.

   - Tickets live in `tickets/` as `TKT-NNN.md`
   - Project-specific build/test/deploy commands and source paths are in `.claude/ticket-config.md`
   - Common commands: `/ticket-new`, `/ticket-list`, `/ticket-investigate`, `/ticket-approve`, `/ticket-review`, `/ticket-ship`
   ```

## Phase 6: Smoke-test instructions

Output a summary and tell the user how to verify the install:

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

The ticket commands are inherited from ~/.claude/commands/ — every project on this machine now has them.
```

## Rules

- NEVER overwrite an existing `tickets/TEMPLATE.md` or existing tickets.
- NEVER overwrite an existing `.claude/ticket-config.md` without using AskUserQuestion to confirm.
- NEVER overwrite `CLAUDE.md` — only append the `## Tickets` section, and only if absent.
- Always confirm detected commands with AskUserQuestion before writing the config. Auto-detection is a starting point, not the final answer.
- If the project isn't a git repo, warn the user but still proceed (the workflow uses git but doesn't require it for `ticket-new`/`ticket-list`).
- If you cannot detect a stack at all, ask the user to type the test/build/deploy commands manually.
