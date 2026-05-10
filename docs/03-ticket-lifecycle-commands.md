# 03 — Ticket Lifecycle Commands

The single-ticket commands. Each operates on one work item (or a
small set, sequenced by the user). The orchestration commands —
`/ticket-chain`, `/ticket-batch`, `/op-run` — are in
[04-ticket-orchestration.md](04-ticket-orchestration.md).

Every command in this section follows the same dispatch pattern at
the top:

```
.claude/plane-config.md exists  → Plane path
.claude/ticket-config.md only   → Markdown path
neither                          → error: run /ticket-install
```

`install.sh:543-554` enforces that every command file (except
`ticket-install.md`) contains the literal string `"Pre-flight: detect
backend"` so the dispatch block can never be silently dropped.

## State machine, both backends

```
                ┌─────────┐
                │  stub   │  (only /brainstorm; only Markdown)
                └────┬────┘
                     │ /ticket-promote
                     ▼
   /ticket-new   ┌─────────┐  /ticket-investigate
   ───────────►  │ Backlog │  ─────────────────────►  Ready
                 │  (open) │                         (proposed)
                 └─────────┘
                     ▲                                  │
                     │                            /ticket-approve
                     │                                  ▼
                     │                          ┌──────────────┐
                     │                          │ In Progress  │
                     │                          │(in-progress) │
                     │                          └──────┬───────┘
                     │                                 │ implementation done
                     │                                 ▼
                     │                          ┌──────────────┐
                     │                          │  In Review   │
                     │                          │  (review)    │
                     │                          └──────┬───────┘
                     │                                 │ /ticket-ship
                     │                                 ▼
                     │                          ┌──────────────┐
                     └─── /ticket-reopen ───────│     Done     │
                                                │   (shipped)  │
                                                └──────────────┘
                          /ticket-defer or /ticket-close
                                 │
                                 ▼
                          ┌──────────────┐
                          │  Cancelled   │
                          │  (deferred / │
                          │   wontfix)   │
                          └──────────────┘
```

In Plane, the state is the literal Plane state plus comment markers
to disambiguate (`deferred:` vs `wontfix:` for Cancelled). In
Markdown, the state is the `status:` frontmatter field plus a folder
move (`tickets/shipped/`, `tickets/deferred/`, `tickets/wontfix/`).

## Identifier resolution (every command)

Every command accepts either a fully-qualified ID (`SMOKE-15`,
`TKT-005`) or a bare number. Resolution:

- **Plane**: prefix from `.claude/plane-config.md` (`Project
  identifier`) → e.g. `15` → `SMOKE-15`.
- **Markdown**: prefix from `.claude/ticket-config.md` (`ID prefix:`,
  default `TKT-`) plus auto-detected zero-padding from existing
  files → `26` → `TKT-026`.

For Plane, every command uses `mcp__plane__retrieve_work_item_by_identifier`
with `expand="labels,state"` for exact-match lookup. The rule at
[commands/ticket-investigate.md:26](../../commands/ticket-investigate.md):
"never use unbounded `list_work_items` scans for explicit ID
resolution."

---

## /ticket-new

**Status:** Functional, both backends.

Body: [commands/ticket-new.md](../../commands/ticket-new.md). 205 lines.

### Inputs

- Free-form `"description"` argument.
- Flags: `--no-parent`, `--parent IDENT-N`, `--follow-up IDENT-N`,
  `--blocks IDENT-N`, `--blocked-by IDENT-N`, `--duplicate-of IDENT-N`.
- Pasted images in the prompt — distilled into prose `Visual context`
  block (lines 60–62 + 158, both backends).

### Plane path

1. Read `.claude/plane-config.md`: project ID, identifier, Backlog
   state ID, label IDs, preview profiles.
2. Parse args; flags can appear anywhere.
3. **Parent inference** (line 47): read `git branch --show-current`,
   parse a Plane identifier out of it
   (`SMOKE-12`, `feat/SMOKE-12-slug`, etc.). If matched, retrieve the
   matched work item and use its `parent` field — not the matched
   work item itself — as the new ticket's parent. If `--parent X` is
   passed, use that explicitly. `--no-parent` skips the inference.
4. **Build description HTML** (line 67): `<p><strong>Type:</strong>
   {type}</p>` + body + Visual context block + Acceptance criteria.
5. **App / preview profile selection** (line 62): if 2+ profiles,
   `AskUserQuestion`; if 1, use it silently; if 0, no `app:*` label.
6. **Create work item** (`mcp__plane__create_work_item`) at line 77.
7. **Resolve relations** (line 88): explicit flags fail-loud on 404;
   implicit references in prose (the regex `\b{IDENT}-\d+\b` on the
   project's own identifier prefix) fail-soft. Each unique target
   gets a `mcp__plane__create_work_item_relation` call.
8. **Output** (line 122): identifier + state + parent + relations +
   "next: /ticket-investigate".

### Markdown path

Lines 162–204. Reads `.claude/ticket-config.md` for tickets dir +
prefix; scans existing tickets recursively (including terminal
subfolders so IDs don't recycle); fills in `tickets/TEMPLATE.md`;
writes new file at `{tickets-dir}/{PREFIX}{NNN}.md`.

### Calls

`/ticket-investigate` is the named next step. No direct invocation —
the user runs it. No back-channel.

### Loose ends

- Implicit relation detection only fires for the **current project's**
  identifier prefix. Cross-project references in prose are silently
  ignored.
- Plane MCP exposes no attachment-upload tool, so pasted images are
  dropped at session end. The Visual context distillation is the only
  artifact that persists. Documented at line 158.
- Empty-body branches (only flags, no description) are not explicitly
  rejected; the agent constructs a description from whatever's left
  after flags are stripped.

---

## /ticket-investigate

**Status:** Functional, both backends.

Body: [commands/ticket-investigate.md](../../commands/ticket-investigate.md). 274 lines.

Most-cited command. Every other lifecycle command assumes the
investigator wrote a parsable Implementation Plan into the ticket.

### Inputs

- One or more ticket IDs (or bare numbers).
- Flag: `--in-given-order` — skip the recommended-implementation-order
  output in multi-ticket mode.

### Routing (line 27–30)

- 1 ID → single-ticket path.
- 2+ IDs → multi-ticket path.

### Plan-mode discipline (line 32–43)

The agent must read `~/.claude/plan-mode.md` (which is the symlink to
`claude-config/plan-mode.md`) and any project-local variant. The plan
must:

- Fit on one screen (~60 lines) per ticket.
- Include a machine-readable `Relevant files` section.
- Include `investigated_at_sha: <SHA>` (line 38).
- Subtract-before-present pass.
- Split delight from fix.
- Flag file-size ceiling violations (e.g. Throughline's 300-line
  rule).
- Name a human ship gate.

### Plane path (lines 47–194)

**Pre-flight** (lines 49–60):

1. Load config.
2. Retrieve work item via `retrieve_work_item_by_identifier` (or
   bounded query if direct helper isn't exposed; never unbounded
   list).
3. **State gate:**
   - Cancelled / Done → STOP, point to `/ticket-reopen`.
   - Already past Backlog → print "already investigated, reading
     existing plan from description"; in multi-ticket mode continue.
     In single-ticket mode, stop.
   - Backlog → proceed.

**Investigation phase** (lines 62–88):

1. Read `CLAUDE.md`, `.claude/ticket-config.md` (key source locations,
   context docs), each context doc in turn.
2. **Parent fetch** (line 67): if `parent` is non-null, retrieve the
   parent work item and read its `description_html` as **read-only
   framing context** — extract guiding principles. Do NOT investigate
   sibling sub-tickets. Do NOT expand scope. The firewall is explicit
   at line 70.
3. Deep-dive: read every relevant file end-to-end (line 76: "do not
   skim").
4. Map call chains; identify interfaces/types/contracts; note
   existing test coverage.
5. For bugs: trace path, identify root cause.
6. For features: identify where the new code fits.
7. Identify regression risks (which tests cover affected code, which
   user flows touch it).
8. **Record `investigated_at_sha`** (line 88): `git rev-parse HEAD` if
   on `main`, else `git rev-parse origin/main`.

**Proposal phase** (lines 90–117): read current `description_html`,
append five HTML sub-sections by `update_work_item`:

```
<h3>Investigation</h3>
<h3>Proposed Solution</h3>
<h3>Implementation Plan</h3>
   <p>{paragraph: what, why, approach}</p>
   <p><strong>Relevant files</strong></p>
   <ul><li><code>path/to/file.ts</code> — what changes</li></ul>
   <p><strong>Steps</strong></p>
   <ol><li>…</li></ol>
   <p><strong>Verification</strong></p>
   <p><strong>Out of scope</strong></p>
```

**Subtract-before-presenting** (line 119–128): explicit review pass
that asks what can be cut, what can be deferred, whether the plan
fits on one screen, whether any `Relevant file` exceeds the project
size ceiling, whether bundling delight with bug fix should be split.

**Finish** (line 130–146):

1. Apply `risk:<level>` label via `update_work_item` with the full
   label list (`[ ...existing_non_risk_labels, risk:<level>_id]`).
2. Transition state → Ready.
3. Post `[investigated_at: <sha>]` comment via
   `create_work_item_comment` (single line, exact marker — drift
   detection parses it).
4. Print summary block.

**Invalid / already-fixed** (line 149–154): transition to Cancelled,
post `wontfix: <explanation>` comment, do NOT append Investigation/Plan.

### Markdown path (lines 198–266)

Same algorithm. Differences:
- Locates ticket file at `{tickets-dir}/{ID}.md`; halts if in
  terminal subfolder (line 205).
- Status gate: must be `stub` or `open`.
- Epic context: if frontmatter has `epic:` field, read **only** the
  `## North star` section of `EPIC-<slug>.md` in same dir (line 215);
  no sibling reads, no brainstorm transcript reads.
- Writes Investigation/Proposed Solution/Implementation Plan into the
  `.md` file directly.
- Sets `status: proposed`, updates `updated:` date.

### Multi-ticket mode (lines 156–185 + 269–274)

Loops every ticket through the per-ticket path including state gates.
Per-ticket progress: `✓ {ID} investigated ({i}/{N}) — risk: {level},
files: {count}`.

After all tickets, computes **recommended implementation order**
(skipped with `--in-given-order`). Five-tier scoring (line 168):

1. Declared dependencies (plus `mcp__plane__list_work_item_relations`
   for native `blocked_by`/`blocking`).
2. Risk / blast radius (high/medium before low).
3. Shared-file conflicts (foundational change first).
4. Quick-win value.
5. Ticket ID (deterministic tiebreaker).

### Loose ends

- Plan-mode discipline check is rhetorical: the agent is told to
  "subtract before presenting" but no automated check fires. Whether
  the plan fits on one screen is judged by the agent against the
  ~60-line target.
- The ".claude/ticket-config.md" file in Plane mode does NOT have a
  per-project size ceiling field; `plan-mode.md`'s discipline cites
  Throughline's 300-line rule as an example but the ceiling is
  hard-coded in the plan-mode discipline file, not surfaced here.
- Multi-ticket mode does not run in parallel. It serializes — useful
  for cohesive understanding, expensive in wall time. For parallel
  investigation, the user runs `/ticket-chain --dry-run` instead.

---

## /ticket-approve

**Status:** Functional, both backends.

Body: [commands/ticket-approve.md](../../commands/ticket-approve.md). 232 lines.

### Plane path (lines 24–134)

**Pre-flight** (line 26–39):

1. Load `plane-config.md` + `ticket-config.md` (Test, Build, Deploy,
   Lint, Main branch).
2. Retrieve work item; 404 → error.
3. **State gate**: must be Ready. Tailored error per other state
   (Backlog → "investigate first"; In Progress → "already being
   implemented"; In Review → "run /ticket-review next").
4. Verify description contains `Implementation Plan` section.
5. Working tree must be clean.

**Phase 1: Branch setup** (lines 41–50):

1. Determine main branch from `Main branch` in `.claude/ticket-config.md`,
   else `git symbolic-ref refs/remotes/origin/HEAD`, else `main`.
   Warn if `master` and suggest `/ticket-install` to migrate.
2. `git checkout {main} && git pull` (allow pull failure if no
   remote).
3. Create feature branch `ticket/{LOWERCASED_ID}-{slugified_title}`,
   under ~50 chars. Example: `ticket/smoke-15-wire-up-automated-test-runner`.
4. Transition state → In Progress.

**Phase 2: Implementation** (lines 53–62): work through Implementation
Plan steps; read every file end-to-end before editing; follow
existing patterns; track progress via `TodoWrite` or per-step
comment.

**Phase 3: Testing** (lines 64–78): Test command from ticket-config;
fix failures including non-introduced regressions; Build command;
Lint command if configured.

**Phase 4: Document results** (lines 80–101): read current
`description_html`, append `<h3>Files Changed</h3>` and
`<h3>Test Report</h3>` sections via `update_work_item`. Read-modify-write;
do not truncate.

**Phase 5: Commit** (lines 103–108): `git add` only the changed
files (not `-A`). Commit message: `{ID}: {short description}`. Atomic
buildable commits.

**Finish**: transition state → In Review.

**Off-the-rails behavior** (line 130): if proposed solution doesn't
work, append `<h3>Approval notes</h3>` to description, transition
state back to Backlog, stop.

### Markdown path

Lines 137–232. Same shape; uses ticket file frontmatter + status
field instead of Plane state.

### Loose ends

- `--target` flag from `/ticket-ship` is not mirrored here; if the
  feature branch is to be cut from a non-main trunk, the user adjusts
  manually after `/ticket-approve`.
- The "Approval notes" off-the-rails path transitions back to Backlog
  but does NOT remove the existing `risk:*` label or
  `[investigated_at:]` marker; those remain for re-investigation.

---

## /ticket-review

**Status:** Functional, both backends.

Body: [commands/ticket-review.md](../../commands/ticket-review.md). 266 lines.

### Plane path (lines 22–151)

**Pre-flight** (lines 24–34):

1. Load configs.
2. Retrieve work item; state gate: must be In Review (tailored errors
   for Backlog, Ready, In Progress).
3. Verify on the feature branch (`ticket/<lowercased-id>-*`); if not,
   try `git branch --list 'ticket/<lowercased-id>-*'` for exactly one
   match; else ask user.

**Phase 1: Automated checks** (lines 36–55):

Split into **blocking** and **informational**:

- Blocking: Tests, Typecheck, Build, Lint, No merge conflicts (via
  `git merge-tree` or throwaway `git merge --no-commit`).
- Informational: Rebased on main (via
  `git merge-base --is-ancestor`), Diff stat (via `git diff {main}
  --stat`).

Omit any blocking check whose command is not configured (do not print
"skipped").

**Phase 2: Human verification checklist** (lines 57–89): build a
markdown checklist with Setup / Core Functionality / Edge Cases /
Regression Checks / Verdict sections. Each item must be specific,
observable, independent, ordered.

**Phase 3: Write to Plane** (lines 93–116): append two HTML sections
to description: `<h3>Automated Checks</h3>` and `<h3>Verification
Checklist (for human)</h3>`.

**Finish** (lines 123–126):

- No state transition. Stays in In Review pending human verdict.
- If any **blocking** check failed, transition state back to In
  Progress and stop. Rebase-behind is informational, never blocking
  (line 126).

### Markdown path

Lines 155–266. Same logic; writes to ticket file's `## Automated
Checks` + `## Verification Checklist (for human)` sections.

### Loose ends

- The "exactly one match" branch-disambiguation logic at line 34 isn't
  defensive against multiple tickets sharing a slug stem (rare but
  possible).
- Re-running `/ticket-review` after a fix doesn't strip the prior
  `<h3>Automated Checks</h3>` block — read-modify-write appends a new
  one. The description grows with every review cycle.

---

## /ticket-preview

**Status:** Functional, both backends.

Body: [commands/ticket-preview.md](../../commands/ticket-preview.md). 117 lines.

### Plane path (lines 22–65)

**Pre-flight** (lines 24–34):

1. Load configs. If `## Preview profiles` is empty, STOP.
2. Retrieve work item; state gate: must be In Progress, In Review, or
   In Progress + delegated label.
3. Feature branch must exist (`ticket/<lowercased-id>-<slug>`).
4. **Soft fallback for missing `app:*` label** (line 33): if no
   `app:*` label, use the profile marked `default: true` AND post a
   `[app:{default-profile}] (no label set; using default)` comment so
   the assumption is auditable. The reason: tickets created in the
   Plane web UI don't get the label automatically.

**Steps**: identical to Markdown path after pre-flight (line 38). The
one Plane addition is a `[preview] — {url}, started {timestamp}`
comment (line 40–44). The marker is load-bearing —
`/ticket-cleanup` reads it as confirmation a preview was launched.

**Markdown path steps** (lines 80–94):

1. Resolve profile (atomic or compound).
2. Compute port per component: `Preview port base + numeric-id +
   component's offset`. Build `{SERVER_PORT, CLIENT_PORT, ...}` for
   cross-component substitution.
3. Working dir: worktree at `.worktrees/ticket-{lowercased-id}/` if
   present; else repo root (after `git checkout {branch}`).
4. **Launch components in dependency order**: substitute placeholders
   in Command, launch in background, capture PID, wait per `Ready
   when:`. On any failure, kill already-launched and STOP.
5. Append per-component line to `.worktrees/ticket-{lowercased-id}/.preview.pid`:
   `{name}  {pid}  {port}`. Write `.preview.meta` with profile,
   components, started_at, branch.
6. Prowl the user.

### State files (per-ticket worktree)

| File | Format | Owner | Reader |
|---|---|---|---|
| `.preview.pid` | `{component}  {pid}  {port}\n` × N | `/ticket-preview` | `/ticket-cleanup`, `/ticket-ship` Phase 7 |
| `.preview.meta` | (format unspecified — agent decides) profile, components, started_at, branch | `/ticket-preview` | `/ticket-cleanup` (informational) |

### Rules (both backends)

- Never on main.
- One preview per ticket at a time.
- Refuse on dirty working tree (repo root only; worktrees are dedicated).
- Literal placeholder substitution.
- Do NOT modify the ticket file, git state, or any code.

### Loose ends

- The format of `.preview.meta` is described as "informational" but no
  schema is given — `/ticket-cleanup` reads it best-effort (line 84
  of cleanup body).
- Port allocation collides if two projects on the same machine share a
  Preview port base and use the same numeric IDs. Documented? No.
- The agent decides which Ready-when condition to use; there's no
  enumeration of expected timeouts. Loose end for tracebacks.

---

## /ticket-ship

**Status:** Functional, both backends.

Body: [commands/ticket-ship.md](../../commands/ticket-ship.md). 245 lines.

### Plane path (lines 22–122)

**Pre-flight** (lines 26–34):

1. Load configs (Test, Build, Deploy, Main branch — or `--target`
   override).
2. Retrieve work item; 404 → error.
3. **State gate**: must be In Review. Cancelled/Done → STOP with
   reopen hint.
4. Verify on feature branch.
5. Clean working tree.

**Phase 1: Final regression test** (rebase-inclusive) (lines 36–43):

1. `git fetch origin {target}` (best-effort).
2. Rebase onto `origin/{target}` (or `{target}` if no remote).
   Conflicts → STOP, no auto-resolve.
3. Tests post-rebase.
4. Build post-rebase.

**Phase 2: Regression report → Plane** (lines 46–58): append
`<h3>Regression Report</h3>` to description.

**Phase 3: Merge** (lines 61–67):

1. `git checkout {target} && git pull`.
2. `git merge ticket/{branch} --no-ff -m "Merge {ID}: {title}"`.
3. Tests on merged target. Failure → `git reset --hard HEAD~1`,
   report, STOP. (Critical: no broken commits on target.)
4. Build on merged target. Same.

**Phase 4: Deploy** (lines 70–78): if Deploy is configured, push +
run Deploy command. Else just push.

**Phase 5: Attach PR link + transition** (line 81–83): if PR URL
derivable, `mcp__plane__create_work_item_link`. Transition state →
Done.

**Phase 6: Cleanup (no archive)** (line 86–90): Plane state Done IS
the archive. Delete feature branch locally + on remote (best-effort).

**Phase 7: Decruft** (lines 93–99) — automatic:

1. Kill preview components: read `.preview.pid`; SIGTERM → SIGKILL in
   reverse launch order; skip `-` PIDs; remove `.preview.pid` and
   `.preview.meta`.
2. `git worktree remove .worktrees/ticket-{lowercased-id}` (fallback
   `--force`, fallback `rm -rf` + `git worktree prune`).
3. **Rollup preview rebuild**: if a `.worktrees/batch-preview-*/`
   exists with a live `.preview.pid`, kill it, recreate scratch
   branch from `{target}` with all remaining In-Review tickets'
   branches merged in identifier order, relaunch.

**Rules** (line 116–121):
- NEVER force push to `{target}`.
- NEVER push if tests/build fail after merge.
- Reset to safe state on any merge/deploy failure.
- Merge commit message MUST reference the Plane identifier.
- Ask for confirmation before pushing to main if first time in the
  project.

### Markdown path (lines 125–245)

Same steps; adds Phase 6 (archive ticket file via `git mv` to
`tickets/shipped/`) since Markdown has no Done state. Brief files
(`{ID}.*.brief.md`) move with the ticket.

### Loose ends

- "Ask for confirmation before pushing to main if this is the first
  time using the workflow in the project" is a soft rule (line 121)
  with no machine-readable signal of "first time."
- The PR link derivation — "from git remote + target compare URL" — is
  not pinned to a specific scheme. GitHub PR vs Gitea PR vs no remote
  vary. The line "or skip if unavailable" (line 82) makes the link
  best-effort.
- The rollup rebuild loops over "all remaining In-Review work items"
  but does NOT re-investigate them against the new `{target}` —
  rollup-as-of-now isn't necessarily mergeable.

---

## /ticket-defer, /ticket-close, /ticket-reopen

**Status:** Functional, both backends.

Bodies:
- [commands/ticket-defer.md](../../commands/ticket-defer.md). 131 lines.
- [commands/ticket-close.md](../../commands/ticket-close.md). 122 lines.
- [commands/ticket-reopen.md](../../commands/ticket-reopen.md). 144 lines.

### /ticket-defer (Plane)

Reason is REQUIRED (line 18). Translated to English. Stops with
"`/ticket-defer` requires a reason." if missing.

Posts `<p><strong>deferred:</strong> {reason}</p>` comment.
The `deferred:` prefix is **load-bearing** (line 42) — `/ticket-status`
and `/ticket-reopen` parse it. Transitions state to Cancelled.
Decruft (worktree + preview) per `/ticket-ship` Phase 7.

Mid-implementation guard (line 33): if state is In Progress or In
Review, warns and requires explicit confirmation.

Markdown path: `git mv` into `tickets/deferred/`, frontmatter
`status: deferred`, append `## Deferred` section. Idempotent across
defer/reopen cycles (line 92): if `## Deferred` already exists, append
new dated entry rather than overwriting.

### /ticket-close (Plane)

Same shape as defer. Posts `<p><strong>wontfix:</strong> {reason}</p>`.
The `wontfix:` prefix distinguishes from deferred — same MCP state
(Cancelled), different audit comment.

### /ticket-reopen (Plane, lines 22–70)

**State gate** (line 28):
- Done or Cancelled → proceed.
- Active → STOP "ticket is already active".

**New active state determination** (line 34):
- From Done (shipped) → Backlog (investigation is stale).
- From Cancelled (cancel comment `deferred:`):
  - Description has Implementation Plan → Ready.
  - Otherwise → Backlog.
- From Cancelled (cancel comment `wontfix:`) → Backlog.
- "When in doubt, use Backlog." (line 40)

Posts `<p><strong>reopened:</strong> from {prior-state} — {reason}</p>`
where `{prior-state}` is derived by scanning comments for the most
recent `deferred:` / `wontfix:` prefix. State transitions to new active
state.

Reason optional but strongly recommended (especially from Done, which
usually means regression).

Does NOT delete history (line 51, 69): all prior Investigation /
Plan / Files Changed / Regression Report / cancel-comment stay in
description.

### Loose ends

- The `deferred:` / `wontfix:` prefix-scanning logic is heuristic —
  comments without those prefixes (e.g. user-typed Plane comments)
  could collide. The agent must scan for the most-recent matching one.
- Markdown path `## Deferred` / `## Closed (wontfix)` sections survive
  reopen (line 110 of reopen). On a defer→reopen→defer cycle, the
  ticket accumulates multiple sections.

---

## /ticket-list, /ticket-status

**Status:** Functional, both backends. Plane paths are URL handoffs.

Bodies:
- [commands/ticket-list.md](../../commands/ticket-list.md). 130 lines.
- [commands/ticket-status.md](../../commands/ticket-status.md). 165 lines.

### /ticket-list (Plane)

**This command is a URL handoff** (line 24). No MCP fetch, no tables.
Reads the `## View URLs` section from `plane-config.md` and prints
one markdown link.

If `## View URLs` is absent (pre-view-URLs install), runs a
**lazy-cache migration** (line 37–53): resolves workspace slug from
`plane-config.md` header → `~/.claude.json` → `AskUserQuestion`,
resolves `PLANE_BASE_URL` from `~/.claude.json` → `AskUserQuestion`,
composes the five URLs, writes the section back.

Auto-reaps stale worktrees inline at the top (line 31), one-line
note if anything reaped.

### /ticket-status (Plane)

Two paths:

- **With `{ID}`** (line 35): `retrieve_work_item_by_identifier` +
  `list_work_item_activities` + `list_work_item_comments`. Parse the
  comment markers (`[investigated_at: <sha>]`, `[delegated_to: <agent>]`,
  `[original_id: <TKT-NNN>]`) and reconstruct lifecycle from state
  history + description sections (table at lines 53–64).
  Render single-ticket timeline with **Next action** as the most
  important line for someone returning cold.
- **No argument** (line 36): URL handoff — print `Active` URL from
  `## View URLs`. Same lazy-cache migration if missing.

Markdown path: same algorithm; reads ticket file frontmatter +
delegation-log section.

### Loose ends

- The lazy-cache migration runs three times (in three separate
  command bodies — `ticket-list`, `ticket-status`, `ticket-promote`)
  with near-identical inline prose. A change to URL templates
  requires editing all three.
- Single-ticket lifecycle reconstruction relies on activity-log + comment
  markers being intact. Plane's activity log is documented as "may
  get rolled up" for long histories (line 90 of status); the body
  explicitly falls back to description-section presence. Reorientation
  on long-running tickets is heuristic.

---

## /ticket-promote

**Status:** Functional, both backends.

Body: [commands/ticket-promote.md](../../commands/ticket-promote.md). 117 lines.

### Plane path

`--all` is a URL handoff (line 29) to the Stubs view URL.
Multi-select + bulk-remove `stub` label happens in Plane's UI.

Explicit-ID path (line 48):
1. Verify `stub` label + Backlog state. Skip with notice otherwise.
2. Remove `stub` label via `update_work_item(labels=<existing
   minus stub>)`.
3. Recurse into parent if it's also stub-labelled. Plan-ticket
   parents auto-promote so `/ticket-investigate`'s parent-read
   logic stays consistent (rule at line 77).

State stays Backlog — promotion is **label-removal only**, not a
state transition (line 56).

### Markdown path

Lines 84–116. Different model: stubs live at `tickets/stub/TKT-NNN.md`
+ `tickets/stub/EPIC-<slug>.md`. `--all` walks every stub file. Bare
numbers match `TKT-{padded}.md` plus letter suffix variants
(`TKT-102a.md`).

Promotion: `mv` from `stub/` to `tickets/`; flip frontmatter `status:
stub` → `status: open`; bump `updated:`; epics auto-promote.

### Loose ends

- Plane `--all` cannot do the recursive parent promotion that the
  explicit-ID path does — Plane's UI bulk action just removes the
  `stub` label from selected children. The user must remember to
  promote the parent plan-ticket too. The notice in the URL handoff
  (lines 32–34) reminds the user about this.

---

## /ticket-cleanup

**Status:** Functional, both backends.

Body: [commands/ticket-cleanup.md](../../commands/ticket-cleanup.md). 130 lines.

### Modes

- `/ticket-cleanup {ID}` — tear down the worktree + preview for this
  ticket regardless of state.
- `/ticket-cleanup --all` — reap every worktree + preview.
- `/ticket-cleanup` (no args) — reap stale only (terminal-state
  tickets or missing).

### Plane path (lines 27–46)

Enumerates `.worktrees/ticket-*/` and `.worktrees/batch-preview-*/`
plus `git worktree list --porcelain`. For each ticket worktree:

- Extract identifier (`ticket-smoke-15` → `SMOKE-15`).
- Resolve via `retrieve_work_item_by_identifier`:
  - 404 → reap as orphaned.
  - State Done or Cancelled → reap.
  - Active state → keep (unless explicit `{ID}` or `--all`).

For `batch-preview-*` worktrees: reap if older than 24h, `--all`, or
no `.preview.pid`.

### Reap action (lines 81–95)

Same contract as `/ticket-ship` Phase 7:

1. Kill preview components: read `.preview.pid` reverse-order, SIGTERM
   then SIGKILL after 3s. Windows: `taskkill /F /PID`. Skip dead PIDs
   and `-` rows. Delete `.preview.pid` and `.preview.meta`.
2. `git worktree remove`. Force on terminal tickets / `--all`. Last
   resort: `rm -rf` + `git worktree prune`.
3. Delete feature branch only if fully merged into main AND ticket is
   in `shipped/`. **Never `-D`** (force-delete) in cleanup.

### Used inline by other commands

`/ticket-list` (line 31), `/ticket-status` (line 30 of status), `/ticket-batch`
(line 32), `/ticket-chain` (line 33) all run the no-arg cleanup
inline at preflight. Silent mode: report only if something was
reaped (line 129).

### Loose ends

- "Older than 24h" for batch-preview worktrees is a hard-coded
  threshold; not surfaced as configurable.
- The branch-deletion safety rule ("only safe-delete + only when
  shipped") leaves orphan branches behind for any ticket that was
  reaped without shipping. Manual `git branch -D` is the user's
  responsibility.

---

## /ticket-delegate, /ticket-collect

**Status:** Functional (Plane), Legacy (Markdown).

Bodies:
- [commands/ticket-delegate.md](../../commands/ticket-delegate.md). 90 lines (Plane summary; full Markdown spec in archive).
- [commands/ticket-collect.md](../../commands/ticket-collect.md). 70 lines.

### /ticket-delegate (Plane)

Phase status gate (lines 32–37):

| Phase | Required state | New state |
|---|---|---|
| (none — full) | Backlog | In Progress + delegated label |
| `investigate` | Backlog | Backlog + delegated |
| `implement` | Ready | In Progress + delegated |
| `review` | In Progress (or post-implement collect) | unchanged, delegated stays |
| `verify investigate` | Ready | Ready + delegated |
| `verify implement` | In Review | In Review + delegated |
| `verify review` | In Review | In Review + delegated |

Per-ticket (lines 41–66): read Plane work item + `CLAUDE.md` +
ticket-config + brief template at
`~/.claude/brief-templates/{phase}.md`. Fill placeholders. Write
brief to `{tickets-dir}/{ID}.{phase-tag}.brief.md`; if no `tickets/`
dir exists in the repo, fall back to `.briefs/`.

Update work item:
- Apply `delegated` label.
- Transition state per gate table.
- Post `[delegated_to: {agent}] — phase: {phase}, brief: {path}`
  comment. **Load-bearing** marker (line 64) — `/ticket-status` and
  `/ticket-collect` parse it.

For `full` or `implement`: create the feature branch
`ticket/<lowercased-id>-<slug>` (line 49). Worktree creation is
optional; `/ticket-delegate` itself doesn't write into `.worktrees/`,
the caller does.

### /ticket-collect (Plane)

Pre-flight (line 24): work item must have `delegated` label AND
`[delegated_to:]` comment. The most recent `[delegated_to:]` comment
identifies which phase was last delegated and where the brief lives.

Phase-specific verification (line 33; full rubric in archive):
- `full` → append `<h3>Delegation Review</h3>` with verdict
  (`approved`/`concerns`/`rejected`).
- `implement` → append Files Changed + Test Report sections.
- `investigate` → no description write (the executing agent already
  wrote Investigation + Plan).

Transition logic (line 39):
- Approved/concerns → remove `delegated` label, transition to In
  Review.
- Rejected → keep `delegated`, state stays.
- Investigate filled → remove `delegated`, state → Ready.
- Implement (branch has commits) → remove `delegated`, state → In
  Review.
- Verify * → keep state, post peer-review comment, remove
  `delegated`.

Post `[collected] — phase: {phase}, verdict: {verdict}` comment.

### Brief templates

[brief-templates/](../../brief-templates/) holds 6 templates referenced
by `/ticket-delegate`:

| Template | Purpose |
|---|---|
| `investigate.md` | hand off /ticket-investigate to another model |
| `implement.md` | hand off /ticket-approve |
| `review.md` | hand off /ticket-review |
| `verify-investigate.md` | peer-review an investigation |
| `verify-implement.md` | peer-review an implementation |
| `verify-review.md` | peer-review a review |
| `full.md` | hand off the full lifecycle |
| `README.md` | template index |

Each is a self-contained markdown brief with placeholders that
`/ticket-delegate` substitutes from the work item + project config.

### Loose ends

- Markdown path of both delegate and collect is condensed in the
  current command body — full spec lives in `archive-commands/`.
  Re-introducing parallel-vs-sequential batch flow into the Plane
  path requires reading the archive.
- The `[delegated_to:]` marker format is brittle prose. If a user
  manually edits the comment (e.g. fixing a typo), parsers downstream
  may misidentify the agent name.
- `.briefs/` fallback dir is created lazily by `/ticket-delegate` when
  there's no `tickets/` dir. Cleanup of stale brief files in
  `.briefs/` is not handled by `/ticket-cleanup`.
