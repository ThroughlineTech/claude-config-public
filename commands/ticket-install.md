# Install the Ticket Workflow Into This Project

You are bootstrapping a project (new or existing) to use the universal ticket workflow. The slash commands themselves live at `~/.claude/commands/ticket-*.md` and are inherited by every project automatically. This command creates the per-project scaffolding the universal commands need: a tickets directory, a template, and a `.claude/ticket-config.md` that records project-specific build/test/deploy commands and key source paths.

## Phase 1: Detect current state

1. Check if `.claude/ticket-config.md` already exists.
   - If YES: switch to **update mode**. Read the existing config, tell the user "Ticket workflow is already installed. I can re-detect the stack and propose updates, or leave things alone." Use AskUserQuestion to ask whether to proceed with re-detection, edit specific fields, or stop.
   - If NO: continue to Phase 2 (fresh install).
2. Check if `tickets/` already exists. If yes, note that it'll be reused (don't overwrite tickets).
3. Check if `CLAUDE.md` exists at the project root.

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

## Phase 4: Confirm with the user

Use **AskUserQuestion** to confirm the proposed config. Ask in one batch (multiple questions per AskUserQuestion call) about:
- Test command (offer the detected default + "other" + "none")
- Build command (same)
- Deploy command (same — "none" is a valid and common answer)
- Whether to proceed with the detected key source locations or edit them

Do NOT proceed without confirmation. Detection isn't always right.

## Phase 5: Write the scaffolding

1. **Create `tickets/TEMPLATE.md`** with this exact content (only if it doesn't already exist — never overwrite):

```markdown
---
id: TKT-XXX
title: ""
type: bug | feature | enhancement
status: open
priority: low | medium | high | critical
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


## Verification Checklist (for human)
<!-- Agent fills this during /ticket-review -->
- [ ] 


## Regression Report
<!-- Agent fills this before merge -->

```

2. **Create `tickets/.gitkeep`** if no tickets exist yet (so the empty dir gets committed).

3. **Create `.claude/ticket-config.md`** with the confirmed values:

```markdown
# Ticket Workflow Config

- Stack: {detected stack}
- Tickets directory: tickets/
- ID prefix: TKT-

## Commands
- Test: {test command, or (none)}
- Build: {build command, or (none)}
- Deploy: {deploy command, or (none)}
- Lint: {lint command, or (none)}

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
