# 02 — `/ticket-install` and the Workspace Contract

`/ticket-install` is the bootstrapper that turns a "regular project"
into one where the universal `/ticket-*` commands work. Where every
other ticket command dispatches between Plane and Markdown, this one
*creates the dispatch state*.

## Status: Functional (Plane path), Legacy (Markdown path)

Body: [commands/ticket-install.md](../../commands/ticket-install.md). 648 lines.

## Inputs

The command takes **no arguments**. Everything is asked interactively
via `AskUserQuestion`. The agent reads:

| Source | Purpose |
|---|---|
| `.claude/plane-config.md` (if present) | Detect "already on Plane → update mode" |
| `.claude/ticket-config.md` (if present) | Detect "on Markdown → ask user" |
| `secrets/.env` (in claude-config repo) | Default to Plane if `PLANE_BASE_URL` is set |
| MCP `mcp__plane__get_me` | Reachability probe |
| `git symbolic-ref refs/remotes/origin/HEAD` | Detect default branch |
| Project tree via `Glob`, `Read`, `xcodebuild -list` | Stack + preview profile detection |
| Existing `package.json`, `Cargo.toml`, `go.mod`, `*.xcodeproj`, etc. | Stack inference |

Pre-flight branch policy ([commands/ticket-install.md:21-29](../../commands/ticket-install.md)):
the command always wants the trunk to be `main`. If the repo's default
is `master` or anything else, it asks whether to rename — and if yes,
runs `git branch -m`, pushes, deletes the remote `master`, and resets
`origin/HEAD`.

## Backend selection (lines 14–19)

```
.claude/plane-config.md present     → Plane (update mode)
.claude/ticket-config.md only       → ask: migrate / stay / stop
neither                              → ask: Plane / Markdown
                                       (default Plane if MCP reachable)
```

Note that the agent reads `secrets/.env` *from the claude-config repo*,
not from the workspace. That requires the agent to know the path.
Implicitly, the agent runs in a Claude session that already has
claude-config installed (otherwise these slash commands are not
visible) — so the secrets check is a `readlink` away. Loose end: the
command body does not document how the agent locates `secrets/.env`
when run outside the claude-config repo. The agent must infer.

## Plane path (canonical)

The Plane path is the documented default and what every active project
uses. It's a 9-phase flow.

### Phase P1: Workspace and project (lines 35–51)

1. **Reachability probe.** `mcp__plane__get_me`. Failure → halt with
   pointer to `secrets/.env` + `./install.sh`.
2. **Project picker.** `mcp__plane__list_projects`. Each result rendered
   as `name + identifier`. Plus a "Create new project" option. Default
   selection: project whose name (case-insensitive) matches the repo
   directory's basename.
3. **Create-new flow.** Asks `Project name` (default = repo basename)
   and `Project identifier` (default = first 5 alphanumeric chars
   uppercased; must be unique in workspace). Calls
   `mcp__plane__create_project`.
4. **Workspace UUID + slug capture** (lines 45–51). The MCP exposes
   `workspace` as a UUID inside project responses but not the `slug`
   directly — the slug is needed for Plane web URLs. Three-step lookup
   is documented:
   1. `~/.claude.json` → `mcpServers.plane.env.PLANE_WORKSPACE_SLUG`.
   2. claude-config's `secrets/.env` (the line `PLANE_WORKSPACE_SLUG=<slug>`).
   3. `AskUserQuestion` fallback.
   The slug ends up in the workspace's `plane-config.md` header (Phase
   P5) and in every entry of the `## View URLs` section.

### Phase P2: Schema seeding (lines 54–87)

Idempotent — re-running is a no-op for already-present items.

**States** (table at line 58):

| Name | Group | Sequence | Color |
|---|---|---|---|
| Backlog | backlog | 15000 | #60646C |
| Ready | unstarted | 25000 | #60646C |
| In Progress | started | 35000 | #F59E0B |
| In Review | started | 40000 | #8B5CF6 |
| Done | completed | 45000 | #46A758 |
| Cancelled | cancelled | 55000 | #9AA4BC |

Special rule at line 68: if Plane shipped its default `Todo` state and
no `Ready` exists, rename `Todo → Ready` via `update_state` rather
than creating + deleting.

**Quirk** (line 71): `create_state` ignores the `sequence` argument
and assigns its own. After creation, the agent re-pins the sequence
via `update_state(sequence=...)`. State UUIDs are recorded for
`plane-config.md`.

**Workspace-standard labels** (line 76):

| Name | Color | Purpose |
|---|---|---|
| `plan-ticket` | `#8B5CF6` | Marks a work item as a plan ticket (parent container) |
| `stub` | `#9CA3AF` | Unpromoted stub from `/brainstorm` or `/plan-new` |
| `delegated` | `#3B82F6` | Currently delegated; agent name in `[delegated_to: ...]` comment |
| `risk:low` | `#10B981` | Regression risk: low |
| `risk:medium` | `#F59E0B` | Regression risk: medium |
| `risk:high` | `#EF4444` | Regression risk: high; gates at Ready until manual approval |

`app:<profile>` labels are deferred to Phase P4 (after preview-profile
detection).

### Phase P3: Stack and preview-profile detection (lines 90–137)

**Stack detection.** Marker-file table at line 96. Stack → default
test/build/deploy commands derived from each. Every detection is
backed by a real read (`Glob`, `Read`, `xcodebuild -list` for Xcode);
"do NOT guess" is explicit at line 94.

**Preview profiles** (line 112). A profile is a named recipe for
running a ticket's feature branch as a live preview. Atomic profiles
are single-process; compound profiles are ordered lists of atomics.
Detection signals:

- `package.json` with one `dev` script → atomic `default`
- `package.json` with `dev:api` + `dev:web` → atomic `server` +
  atomic `client` + compound `fullstack`
- Monorepo `apps/api/` + `apps/web/` → same as above with cd-prefixed
  commands
- `docker-compose.yml` → atomic `default`
- Vercel/Netlify config → atomic `preview` with `mode: rollup`
- Single-scheme Xcode project → one atomic per platform
- Multi-scheme Xcode project → atomic per scheme + compound `pair`
- Library with no runtime → no profiles

**Atomic profile fields** (lines 126–128): Command (with
`{PORT}/{ID}/{BRANCH}/{WORKTREE}/{<OTHER>_PORT}` placeholders), Port
offset (defaults: 0, 1000, 2000…; reserve 999 per component for
rollup), Ready when (`http {PATH}` / `log {PATTERN}` / `delay
{SECONDS}` / `command-exit`), Sequential (true for singleton resources
like the iOS simulator), Depends on.

**Compound fields**: ordered Components list + Default flag (only one
profile is the default).

**Preview mode** (line 134):
- `auto` — `/ticket-batch` tries rollup first, falls back to individual
  on conflict. Default for webapps.
- `rollup` — always combine. Fail on merge conflict.
- `individual` — one preview per ticket. Default if any profile is
  Sequential (e.g. iOS).

### Phase P4: Confirm + create app labels (lines 140–149)

Single batched `AskUserQuestion` covering test/build/deploy/lint
commands and every detected preview profile. Each `app:<profile>`
label is created via `create_label` against the workspace; UUIDs
captured.

### Phase P5: Write `.claude/plane-config.md` (lines 152–225)

Pre-built **View URLs** (lines 159–166) — five Plane web URLs that
display commands hand off to without further MCP calls:

| View | URL filter |
|---|---|
| Active | `state_group=backlog,unstarted,started&order_by=-priority` |
| In Review | `state_group=started&order_by=-priority` |
| Stubs | `labels={stub-uuid}&order_by=-priority` |
| All | `order_by=-priority` |
| Work item template | `/{IDENT}-{seq}` (no query) |

**Schema written.** The full template is at lines 171–226. Key
sections of `<workspace>/.claude/plane-config.md`:

```markdown
# Plane Backend Config

- Backend: plane
- Workspace slug: {slug}
- Workspace UUID: {uuid}
- Project name: {name}
- Project ID: {uuid}
- Project identifier: {IDENT}

## State IDs
- Backlog: {uuid}
- Ready: {uuid}
- In Progress: {uuid}
- In Review: {uuid}
- Done: {uuid}
- Cancelled: {uuid}

## Label IDs (workspace-standard)
- plan-ticket: {uuid}
- stub: {uuid}
- delegated: {uuid}
- risk:low: {uuid}
- risk:medium: {uuid}
- risk:high: {uuid}

## Label IDs (app:<profile>, per-project)
- app:{profile1}: {uuid}
…

## View URLs
- Active: …
- In Review: …
- Stubs: …
- All: …
- Work item (template): …
```

This file is the **single contract** every Plane-backed ticket-*
command reads. The Plane path of every command begins with "Load
config from .claude/plane-config.md" — see for example
[commands/ticket-investigate.md:51](../../commands/ticket-investigate.md),
[commands/ticket-approve.md:28](../../commands/ticket-approve.md),
[commands/ticket-ship.md:27](../../commands/ticket-ship.md).

### Phase P6: Write `.claude/ticket-config.md` (Plane mode) (lines 228–268)

Plane mode still writes ticket-config.md because preview / review /
ship commands read build/test/deploy commands and preview profiles
from it. Differences from Markdown mode (line 230): no `Tickets
directory:` field, no `ID prefix:` field. Schema (lines 234–268):

```markdown
# Ticket Workflow Config

- Stack: {detected}
- Backend: plane (see .claude/plane-config.md for project UUIDs)
- Main branch: main

## Commands
- Test: {cmd or (none)}
- Build: {cmd or (none)}
- Deploy: {cmd or (none)}
- Lint: {cmd or (none)}

## Preview settings
- Preview mode: {auto | rollup | individual}
- Preview port base: 3000

## Preview profiles

### {profile-name}  ({atomic|compound})
- Command: {with placeholders}
- Port offset: {N}
- Ready when: {http /health | log "..." | delay 5 | command-exit}
- Sequential: {bool}
- Depends on: [{other}, ...]

### {compound-name}  (compound, default)
- Components: [{atomic1}, {atomic2}]

## Key source locations
- {path} — {description}

## Context docs
- {path}
```

### Phase P7: Project scaffolding (lines 270–291)

1. **Update workspace `CLAUDE.md`** — appends a `## Tickets` section
   that documents the Plane backend + identifier prefix + common
   commands. Won't overwrite an existing section.
2. **Add `.worktrees/` to `.gitignore`.** `/ticket-batch` and
   `/ticket-chain` write per-ticket worktrees + PID/meta files there.
3. **Do NOT create `tickets/`.** Plane mode has no on-disk ticket
   files (line 291).

### Phase P8: Migration-mode bookkeeping (lines 293–299)

Only when the user picked "migrate to Plane" from a Markdown project:

- Do NOT delete `tickets/`. Stays for the duration of Plan 3.
- Do NOT edit the existing `.md` tickets.
- Print a one-line reminder that Plan 3 will import them with
  `[original_id: TKT-NNN]` markers.

### Phase P9: Smoke output (lines 301–327)

A summary block listing project identifier, seeded states, seeded
labels, files written, detected stack, and verification commands.

### Rules (Plane path) (lines 329–335)

- NEVER delete existing Plane states or labels. Seeding is additive +
  rename-only.
- NEVER overwrite `plane-config.md` without confirmation.
- If MCP unreachable, stop cleanly — no partial config files.
- `app:<profile>` labels are per-project (each project creates its own
  copy; UUIDs differ across projects but names match).
- If a project with the chosen identifier already exists, Plane rejects
  the create — user picks a different identifier.

## Markdown path (legacy)

Lines 339–648. Same shape (detect → confirm → write scaffolding →
smoke), but writes `.claude/ticket-config.md` (with `Tickets directory:
tickets/`, `ID prefix: TKT-` fields) and a `tickets/TEMPLATE.md` with
fixed frontmatter.

**Schema differences from Plane mode:**
- `.claude/ticket-config.md` includes `Tickets directory:` and
  `ID prefix:` fields (lines 558–559).
- `tickets/TEMPLATE.md` is created (line 484). Frontmatter:
  `id, title, type, status, priority, app, branch, created, updated`.
  Body sections: `Description`, `Reproduction Steps (bugs only)`,
  `Acceptance Criteria`, then agent-filled: `Investigation`,
  `Proposed Solution`, `Implementation Plan`, `Files Changed`,
  `Test Report`, `Automated Checks`, `Verification Checklist (for
  human)`, `Regression Report`.

**Update-mode migrations** (Phase 4b, lines 461–477):
- Flat `Preview:` → atomic profile named `default` with offset 0
- Add missing `Preview mode` / `Preview port base`
- Add `app:` field to `tickets/TEMPLATE.md`
- Backfill `app:` field on active + deferred ticket files (skip
  shipped/closed)
- Add `.worktrees/` to gitignore

**Status:** Legacy. Plan 3 will remove this path entirely; for now the
on-disk Markdown projects coexist on the same machine as Plane projects
because the dispatch block at the top of every command reads only
`.claude/plane-config.md` to decide.

## Idempotency

The Plane path is idempotent in three places (lines 55, 71, 332):
- State seeding: only creates missing states; renames `Todo → Ready`
  if applicable.
- Label seeding: creates missing labels.
- File writes: `plane-config.md` is overwritten only in update mode
  with confirmation; `ticket-config.md` and `CLAUDE.md` are merged in
  rather than replaced.

The Markdown path is idempotent for `tickets/TEMPLATE.md` (NEVER
overwrite, line 642), `.claude/ticket-config.md` (NEVER without
confirmation, line 643), and `CLAUDE.md` (only append `## Tickets` if
absent, line 644).

## Failure modes

| Failure | Behavior |
|---|---|
| Plane MCP unreachable on first call | Halt with pointer to `secrets/.env` + `./install.sh` (line 37) |
| `mcp__plane__create_project` rejects duplicate identifier | Asks user for a different identifier (rule line 335) |
| `mcp__plane__create_state` returns wrong sequence | Re-pins via `update_state` (line 71) |
| Repo's default branch is `master` | Asks user; rename if yes; record actual name in ticket-config if no (line 23–28) |
| Pre-existing `plane-config.md` in update mode | Overwrite only with confirmation (line 332) |
| `secrets/.env` missing PLANE_BASE_URL | Default to Markdown backend (line 19) |
| Working tree dirty | Not checked here; downstream commands check |
| Stack undetectable | User types commands manually (Markdown path rule line 647; Plane path silent) |

## Ties to the rest of the system

- **TravelAgent extension `bindProject` command** writes a *stub*
  `<workspace>/.claude/plane-config.md` with only `- Backend: plane`
  and `- Project ID: {uuid}` —
  [extension/src/api/planeClient.ts:222-231](../../extension/src/api/planeClient.ts).
  That stub is enough for the dispatch block at the top of every
  ticket-* command to pick the Plane path, but it does NOT contain
  state IDs, label IDs, or view URLs. The first time a ticket-*
  command runs against that stub, it must look up state IDs and label
  IDs via MCP — which most commands don't do (they assume the schema
  was seeded by `/ticket-install`). The TravelAgent extension's
  bootstrap UI runs `claude /ticket-install` in a fresh terminal in
  the workspace folder via
  [extension/src/actions/ticketActions.ts:160-181](../../extension/src/actions/ticketActions.ts)
  precisely to fill in the missing schema. See
  [06-extension-and-external-contracts.md](06-extension-and-external-contracts.md).
- **`~/.claude/plane-config.md`** is a different file with a different
  schema written by `install.sh:482-485`. Holds three lines of global
  credentials, read by the TravelAgent extension at
  `extension/src/api/planeClient.ts:144`. Not read by any ticket-*
  command in claude-config.

## Loose ends

- **Lazy-cache migration for `## View URLs`.** `/ticket-list`
  ([commands/ticket-list.md:36-53](../../commands/ticket-list.md)) and
  `/ticket-status`
  ([commands/ticket-status.md:42-47](../../commands/ticket-status.md))
  and `/ticket-promote --all`
  ([commands/ticket-promote.md:38-44](../../commands/ticket-promote.md))
  each contain inline logic to compose and append the `## View URLs`
  section if it's missing — for projects whose `plane-config.md` was
  written before the View URLs feature shipped. There's no separate
  `migrate-view-urls` command. The migration runs the first time any
  of those three commands is invoked. Three duplicates of the same
  procedure live in the three command bodies. Not consolidated.
- **No corresponding `/ticket-uninstall`.** Removing the Plane backend
  from a project requires manual deletion of `plane-config.md` +
  `ticket-config.md` + the `## Tickets` section in `CLAUDE.md`.
  Plane states/labels/work items are not deleted (the rule at line 331
  says "NEVER" delete them).
- **Schema versioning.** Neither `plane-config.md` nor `ticket-config.md`
  carries a schema version. The lazy-cache migration handles missing
  `## View URLs` by detecting the section's absence; a future schema
  bump that adds new fields would have no machine-readable signal.
- **Stub `plane-config.md` from TravelAgent vs canonical.** The
  TravelAgent extension's stub write at
  `extension/src/api/planeClient.ts:222-231` does not preserve any
  fields written by `/ticket-install`. If a project that ran
  `/ticket-install` is later rebound through the extension, the
  extension's path either updates the existing `Project ID:` line in
  place (line 215–219) or appends a new line (line 217–219). The
  extension's behavior is "preserve existing content + replace the
  one Project ID line" which is safe — but only by accident, since the
  schema is brittle Markdown rather than structured JSON.
- **`Phase P3` does not record `xcodebuild`-discovered schemes
  anywhere persistent.** The detection runs every time `/ticket-install`
  is re-run; on a project with many schemes the user re-confirms the
  same picker each time.
- **Migration of legacy `tickets/`.** Phase P8 (line 293) reminds the
  user that "Plan 3 will import them" but `commands/` does not contain
  any plan-3 import command. The `bin/migrate-markdown-to-plane`
  helper exists ([bin/migrate-markdown-to-plane](../../bin/migrate-markdown-to-plane))
  but is not referenced from `/ticket-install` and not exercised here.
