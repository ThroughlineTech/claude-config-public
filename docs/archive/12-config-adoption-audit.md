# Config Adoption Audit

**Last run:** 2026-04-13
**Scope:** All repos under `~/src/`

This document records which repos use the claude-config ticket system, what local modifications exist, and which modifications are candidates for upstreaming into the base config. It also includes a reusable prompt so any agent can re-run the same audit.

---

## Repo Inventory

### Full Ticket System (commands + ticket-config + tickets/)

| Repo | Commands Source | Custom Commands |
|------|----------------|-----------------|
| `_project-blast/rejog-blast` | Global symlinks | `update-architecture.md` |
| `_project-rejog/rejog-ios` | Global symlinks | `update-architecture.md` |
| `_project-rejog/rejog-safety` | Global symlinks | `update-architecture.md` |
| `_project-throughline/throughline-interview-v2` | **Local copies** (6 files) | None |

### Partial Setup (ticket-config + tickets/, no local commands)

These repos rely entirely on global symlinked commands:

- `claude-intercom`
- `mac-remote-deploy`
- `_project-sqzarr/sqzarr`
- `_project-throughline/cards-for-bongs`
- `_project-throughline/theimagedepot`
- `_project-throughline/throughline-interview`

### .claude/ Directory Only (no ticket config)

These have a `.claude/` directory (usually `settings.json`) but no ticket workflow:

- `_project-loomwork/loomwork`
- `_project-rejog/rejog-backend`, `rejog-docs`, `rejog-prototype`, `rejog-public-web`
- `_project-solar/solardocs`, `solarseed`
- `_project-throughline/codenoscopy`, `openbaseline`, `sidefire`, `sidefire2`, `throughlinetech`

### No .claude/ at All

Parent directories, archived repos, and non-code projects (18 total).

---

## Generalizable Patterns Found

These are process improvements discovered in project CLAUDE.md files that are **not repo-specific** and could apply to any project using the ticket system.

### Tier 1 — Strong upstream candidates

#### 1. "Don't loop on failures" rule
**Source:** `_project-rejog/rejog-ios/CLAUDE.md`

> Don't loop on failures. After 2-3 failed attempts, stop and present the problem with options.

**Why upstream this:** Prevents infinite retry loops in AI-assisted workflows. Forces deliberation over brute force. Applicable to every project.

#### 2. Quality gate before ticket completion
**Source:** `_project-rejog/rejog-ios/CLAUDE.md`

> Do NOT skip steps 4-7. Do NOT declare a ticket done without a green build and test run.

The full checklist:
1. Read the ticket doc first. Understand the scope.
2. Investigate the codebase — verify file paths, line numbers, root causes. Ticket docs may be stale.
3. Make the changes.
4. Build.
5. Fix build errors before moving on. If errors are pre-existing and unrelated, fix them anyway.
6. Run tests.
7. Verify no regressions.
8. Update the ticket doc status.

**Why upstream this:** Reinforces the existing `feedback_automated_verification` pattern. The "fix pre-existing errors too" rule is a strong addition — it prevents broken-window accumulation.

#### 3. ADR enforcement pattern
**Source:** `_project-rejog/rejog-ios/CLAUDE.md`

> Read `docs/architecture/` before starting any feature, refactor, or sprint. ADRs are laws — not suggestions. If your work touches [relevant areas], you must comply with the active ADRs or formally amend them. Proceeding without reading them is not allowed.

**Why upstream this:** Projects with architectural constraints need a way to make those constraints binding. This pattern is framework-agnostic — just requires a docs directory and a rule in CLAUDE.md.

#### 4. Proof-of-completion protocol
**Source:** `_project-throughline/throughline-interview-v2/CLAUDE.md`

> - One item at a time. Do not batch. Do not skip ahead.
> - Check off only when truly done. Not "mostly done." Not "compiles." Done means the requirement is fully met with evidence.
> - No TODO stubs. If a handler, callback, or function body is `console.log` or `// TODO`, the item is NOT done.
> - If you can't complete an item, mark it `- [BLOCKED] P3-015: reason here` and move to the next.
> - Do not reorder items. They are in dependency order for a reason.

**Why upstream this:** Prevents stub commits and forces explicit evidence of completion. The `[BLOCKED]` metadata pattern is useful for any checklist-driven workflow.

### Tier 2 — Worth considering

#### 5. Documentation regeneration command
**Source:** `_project-rejog/rejog-ios/.claude/commands/update-architecture.md`

A command that reads the full codebase, diffs against existing architecture docs, and rewrites only changed sections. Key rules:
- Do not preserve stale content — if something no longer exists, remove it
- Do not invent or assume — only document what exists in source files
- Note removals explicitly in document headers

**Why consider:** Generalizable "keep docs in sync with code" protocol. Could become a standard command if parameterized (which docs dir, which source dirs).

#### 6. Product boundary enforcement
**Source:** `_project-rejog/rejog-ios/CLAUDE.md`

> - `shared` code ships to both products — treat changes to it like public API changes.
> - Mixed files need dedicated refactoring. Tracked by follow-up tickets.

**Why consider:** Useful pattern for monorepos and multi-product repos, but only applies to a subset of projects.

---

## Repo-Specific Modifications (not upstream candidates)

### throughline-interview-v2: Local command copies

Has local copies of 6 ticket commands (approve, investigate, list, new, review, ship). All are **simplified and hardcoded** for npm/Cloudflare Workers — fewer features than canonical versions, no config-driven flexibility. These represent a project that predates the current symlink-based install and was never upgraded.

**Action:** Consider running `/ticket-install` to upgrade to symlinked commands.

### sidefire2, codenoscopy, openbaseline, throughlinetech: Local settings.json

These have project-level `.claude/settings.json` files with custom permission lists. This is working as designed — project-specific permissions belong in the project.

### All ticket-config.md files

Stack-specific build/test/deploy commands. This is the intended customization point — no action needed.

---

## Recommendations

1. **Add "don't loop on failures" to global CLAUDE.md** — one line in Universal Conventions.
2. **Add quality gate language to ticket-approve and ticket-ship** — "Do not mark complete without green build + tests." This reinforces the existing automated verification feedback.
3. **Document the ADR enforcement pattern** in `docs/02-ticket-workflow.md` as an optional section projects can add to their CLAUDE.md.
4. **Upgrade throughline-interview-v2** to use symlinked commands via `/ticket-install`.
5. **Consider a `ticket-update-docs` command** based on the rejog-ios `update-architecture.md` pattern, parameterized via ticket-config.md.

---

## Reusable Audit Prompt

The following prompt can be given to any agent with access to a `src/` directory to produce a comparable report. Copy it verbatim.

````markdown
# Claude Config Adoption Audit

Scan all repositories under the user's `src/` directory (or equivalent) and produce a structured report about claude-config ticket system adoption and local modifications.

## Step 1: Inventory

For every subdirectory (recursing one level into `_project-*` parent dirs):

1. Check for `.claude/` directory
2. Check for `.claude/ticket-config.md`
3. Check for `.claude/commands/` containing `ticket-*.md` files
4. Check for `tickets/` directory
5. Check for `CLAUDE.md`
6. Check for `.claude/settings.json` and `.claude/settings.local.json`

Categorize each repo as:
- **Full**: Has ticket-config.md + tickets/ + ticket commands (symlinked or local)
- **Partial**: Has ticket-config.md + tickets/ but no local ticket commands (relies on global symlinks)
- **Minimal**: Has .claude/ but no ticket config
- **None**: No .claude/ directory

## Step 2: Detect modifications

For repos categorized as Full or Partial:

1. **Read every CLAUDE.md** and extract sections that describe PROCESS rules (not repo-specific paths, build commands, or stack descriptions). Look for:
   - Workflow rules (e.g., "always run X before Y")
   - Quality gates (e.g., "don't mark done until tests pass")
   - Anti-patterns (e.g., "don't do X")
   - Enforcement patterns (e.g., "read docs/X before starting")
   - Completion criteria (e.g., "no TODO stubs")

2. **Check for custom commands** in `.claude/commands/` that aren't standard ticket-* commands. Read their full content.

3. **Check for local copies of ticket commands** (not symlinks). If found, diff against the canonical versions in the claude-config repo (usually at `~/src/claude-config/commands/` or `~/.claude/commands/`). Note whether modifications are improvements or simplifications.

4. **Read `.claude/settings.json`** for non-default configurations (hooks, custom permissions beyond the base set, environment variables).

## Step 3: Classify modifications

For each modification found, classify as:

- **GENERALIZABLE**: Process improvement that could apply to ANY project regardless of stack. Examples: "run tests before shipping", "stop after 3 failures", "no TODO stubs".
- **REPO-SPECIFIC**: Customization tied to this project's stack, paths, or domain. Examples: "use npm run test", "update docs/api-reference.md", "deploy to Cloudflare".

Quote generalizable modifications verbatim.

## Step 4: Produce report

Output a markdown report with these sections:

1. **Repo Inventory** — table of all repos with their category
2. **Generalizable Patterns Found** — each pattern with source repo, verbatim quote, and why it's generalizable
3. **Repo-Specific Modifications** — brief notes on what was found (no need to quote)
4. **Recommendations** — which generalizable patterns should be upstreamed to the base config

## Notes

- "Upstream" means adding to the shared claude-config repo so all projects benefit
- The ticket system uses `ticket-config.md` for per-project settings (build/test/deploy commands, stack info) — these are EXPECTED to differ per repo and are not "modifications"
- Commands installed via symlinks from `~/.claude/commands/` are canonical; local copies in `.claude/commands/` within a repo are modifications worth examining
````

---

## Audit History

| Date | Runner | Scope | Report |
|------|--------|-------|--------|
| 2026-04-13 | Claude (this session) | `c:/Users/fubar/src/*` | This document |
