# 04 — Ticket Orchestration

The parallel commands. `/ticket-chain` and `/ticket-batch` orchestrate
the per-ticket lifecycle commands across many tickets in worktrees.
`/op-scaffold` and `/op-run` are a separate, larger orchestration
surface for multi-plan refactors that don't fit a single ticket.

`/ticket-chain` is the surface TravelAgent's coordinator targets when
it dispatches work into a Claude session
([extension/src/actions/ticketActions.ts:94](../../extension/src/actions/ticketActions.ts):
`/ticket-chain {identifier1} {identifier2}` for multi-ID, otherwise
`/ticket-{verb} {identifier}`).

## /ticket-chain

**Status:** Functional (Plane path, abbreviated body — defers to
markdown spec for shared phases). Functional (Markdown path,
documented in archive).

Bodies:
- [commands/ticket-chain.md](../../commands/ticket-chain.md) — current,
  106 lines. Plane-specific phases inline; Markdown phases a summary
  with explicit pointer to archive.
- [archive-commands/ticket-chain.md](../../archive-commands/ticket-chain.md)
  — original, 480 lines. The full Markdown-path spec including
  investigator prompt template, conflict-detection regex, review
  checklist template, prowl format. The current body cites this file
  as the canonical spec for shared phases.

### Inputs

- List of ticket IDs (any mix of identifiers and bare numbers).
- No arguments → operate on every active-Backlog ticket.
- Flags:
  - `--dry-run` — investigate + show wave plan, stop.
  - `--sequential` — no parallelism. Each ticket investigated +
    implemented + previewed one at a time. Still stops for review
    checklist unless `--ship`.
  - `--ship` — auto-merge after implement. No preview, no review
    checklist. Fire-and-forget.

### Pre-flight

- Backend dispatch (line 12–15).
- Plane: load `plane-config.md` + `ticket-config.md`. Read Test/Build/Deploy +
  Main branch (or `--target` override).
- Working tree must be clean. On main.

### Phase 0: Resolve set + reap stale (lines 31–41)

1. Run `/ticket-cleanup` no-arg logic inline.
2. Resolve ticket set:
   - **Explicit IDs**: `retrieve_work_item_by_identifier` per ID.
     Terminal state → STOP.
   - **No IDs**: `list_work_items(state_ids=[<backlog id>])`.
3. Accept only Backlog and Ready states. Reject In Progress, In
   Review, terminal.
4. Sort by `sequence_id`; preserve user's argument order as
   tiebreaker (load-bearing for cycle resolution).

Empty set → STOP.

### Phase 1: Investigate all (parallel) (lines 43–46)

Spawn one subagent per Backlog-state ticket, in parallel (single
message with multiple `Agent` tool calls). Each subagent runs the
equivalent of `/ticket-investigate` writing back to Plane via MCP:

- Append Investigation/Proposed Solution/Implementation Plan to
  `description_html` (read-modify-write).
- Apply `risk:<level>` label.
- Post `[investigated_at: <sha>]` comment.
- Transition state to Ready.

Tickets already at Ready skip this phase.

The full investigator prompt template is in
[archive-commands/ticket-chain.md:50-66](../../archive-commands/ticket-chain.md):

> You are investigating ticket {ID}…
> 1. Read the ticket's Description and Acceptance Criteria.
> 2. Read CLAUDE.md, .claude/ticket-config.md, and all context docs
>    listed in the config.
> 3. Deep-dive…
> 4. Write into the ticket file: Investigation, Proposed Solution,
>    Implementation Plan (precise enough that another engineer with
>    no context could implement), Dependencies (other ticket IDs in
>    the batch that must ship before this one. **Err on the side of
>    declaring a dependency.**)
> 5. Transition status to proposed.
> 6. If invalid or already fixed, set status to closed.
> Report: regression risk, dependency list, files touched.

### Phase 2: Dependency graph + waves (lines 48–58)

Two input sources:

1. **Declared dependencies** — grep for ticket identifiers in
   "depends on" / "blocked by" prose in the Implementation Plan.
2. **Native `work_item_relations`** via
   `mcp__plane__list_work_item_relations`:
   - `blocked_by` → hard edges.
   - `relates_to` → soft overlap info (informational).

**File-overlap heuristic** (Markdown spec; line 88 of archive — Plane
body inherits via "see archive"): extract file paths from each
ticket's Implementation Plan. **Hub-file threshold**: file touched by
3+ tickets is a hub (router, registry, shared component). Hub files
do NOT create dependency edges; they are recorded as **conflict
notes** in the final report. The investigator's declared dependencies
are the right signal for hub files.

**Cycle resolution** (archive line 104): collapse cycles into
sequential sub-chains using the user's original argument order as the
tiebreaker. Never errors out. Never asks the user.

**Wave computation** (archive line 109):
- Wave 1: in-degree 0.
- Wave N: deps entirely in waves 1..N-1.

`--dry-run`: print wave plan and stop (line 56 of current).

### Phase 3: Implement (per wave) (lines 60–67)

For each wave, in order:

**Step A — Worktrees** (archive line 156): branch name
`ticket/{lowercased-id}-{slugified-title}`. Reuse if branch already
set on the ticket. `git worktree add .worktrees/ticket-{lowercased-id}
{branch}` (or `-b {branch} {main}`).

**Step B — Re-investigate** (waves 2+ only, archive line 164): the
codebase has changed since original investigation. Spawn one
subagent per ticket in this wave, in parallel, with a re-investigation
prompt (full prompt at archive line 168–177): pull latest main into
worktree, re-read relevant files, update Investigation / Proposed
Solution / Implementation Plan in the ticket, mark resolved
dependencies as `[shipped]`. Re-check regression risk; if a
re-investigated ticket now shows `high`, remove from chain and add
to paused list.

**Step C — Implement** (archive line 184): one subagent per ticket in
the wave, in parallel. Worker prompt at line 187–203:

> You are implementing ticket {ID} in an isolated git worktree at
> `.worktrees/ticket-{lowercased-id}/`…
> 1. Read the ticket's Implementation Plan…
> 4. Run {Test} — fix failures.
> 5. Run {Build} — must be clean.
> 6. Fill in Files Changed and Test Report sections.
> 7. Commit each logical unit with `{ID}: ...` messages.
> 8. Transition status to review.
> 9. On failure: do NOT ship broken code.
>
> All work happens in the worktree. Do NOT touch the main repo
> directory.
>
> Report back: branch, commit count, files changed, test count,
> build status, success/failure.

Per-ticket Plane state transitions (current line 68): Ready → In
Progress → In Review.

**Step D — Ship (sequential within wave; `--ship` only)** (archive
line 209): for each successful ticket in this wave, in ID order:

1. `git checkout {main}` + pull latest.
2. Rebase ticket branch onto `origin/{main}`.
3. Tests + build after rebase.
4. Merge with `--no-ff -m "Merge {ID}: {title}"`.
5. Tests + build on merged main. **Failure → `git reset --hard
   HEAD~1`. Continue to next ticket in wave.**
6. Push to origin.
7. Deploy if configured.
8. Delete feature branch.
9. Archive (Markdown only) or transition to Done (Plane).
10. Cleanup worktree + preview.

Wait for all subagents in the wave to complete (tests + build pass
per ticket-config). On any failure, STOP and report — do not advance
to next wave.

**Cascading failures** (archive line 246): if a ticket in wave N
fails, dependents in wave N+1 are removed from the chain ("skipped —
dependency TKT-XXX failed").

**Between waves in default mode** (archive line 244): the chain
**merges to main but does not deploy** between waves. The
preview/staging deploy happens once after all waves complete.

### Phase 4: Preview + review checklist (default; lines 70–75)

Skip entirely if `--ship`.

**Step A — Deploy to preview** (archive line 254): per Preview mode
in `.claude/ticket-config.md`. For multi-wave chains where tickets
haven't been merged to main, create a scratch branch merging all
successful ticket branches and deploy from that.

**Step B — Automated verification** (archive line 266): tests,
typecheck, build, lint, branch rebased on main, no merge conflicts.
Per-ticket. Failures flagged prominently in the checklist but do NOT
remove the ticket — human reviewer decides.

**Step C — Generate review checklist** (archive line 282): single
consolidated markdown file at
`{tickets-dir}/CHAIN-REVIEW-{YYYY-MM-DD-HHMM}.md`. Per-ticket
sections: branch, files changed, tests added, risk, what changed,
acceptance criteria, automated checks (with detailed pass/fail),
verification steps (specific + observable), edge cases, regression
checks, verdict checkbox.

**Step D — Commit the checklist** (archive line 374): `ticket-chain:
review checklist for {N} tickets`.

Plane path equivalent (current line 73): post `[preview]` comment per
ticket; emit `CHAIN-REVIEW-{timestamp}.md`; prowl once.

### Phase 4 (`--ship` mode; lines 77–78)

For each In-Review ticket, run `/ticket-ship` equivalent. Sequential.
Stop on any failure.

### Phase 5: Final report + prowl (archive line 378)

Single report block listing requested / implemented / paused / failed
/ skipped / invalid counts, preview URL, review checklist path,
wave-by-wave breakdown, hub file conflicts, next steps.

**One prowl per chain run**, never per-ticket / per-wave (rule at
archive line 477):

- Default: `Chain ready — {n} tickets for review`, priority 0.
- `--ship`: `Chain complete — {n} shipped in {W} waves`, priority 0.
- Any failures: `Chain done — {n} ready, {f} failed`, priority 1.

### Worktree protocol summary

| Path | Created by | Removed by |
|---|---|---|
| `.worktrees/ticket-{lowercased-id}/` | `/ticket-chain` Phase 3A; `/ticket-batch` Phase 4 | `/ticket-ship` Phase 7; `/ticket-cleanup`; `/ticket-defer`/`/ticket-close` decruft |
| `.worktrees/ticket-{lowercased-id}/.preview.pid` | `/ticket-preview` Step 5 | `/ticket-cleanup` reap; `/ticket-ship` Phase 7 |
| `.worktrees/ticket-{lowercased-id}/.preview.meta` | `/ticket-preview` Step 5 | same as `.preview.pid` |
| `.worktrees/batch-preview-*/` | `/ticket-batch` rollup mode | `/ticket-cleanup` reaps if older than 24h or `--all`; `/ticket-ship` Phase 7 rebuilds rollup |

Branch naming: `ticket/{lowercased-id}-{slugified-title}`, slug rule
"lowercase, replace non-alphanum with `-`, collapse dashes, trim,
under ~50 chars" ([commands/ticket-approve.md:49](../../commands/ticket-approve.md)).

### Loose ends

- The current `/ticket-chain.md` body (106 lines) is much shorter
  than the archive (480 lines). Many phases say "match the markdown
  path's logic" or "see the archive." This is by design (line 6,
  current header: "abbreviated — full spec in
  archive-commands/ticket-chain.md") but a reader who only opens the
  current body will miss the investigator prompt template, the
  worker prompt, the cycle-resolution logic, the hub-file threshold,
  and the prowl format.
- The investigator prompt at archive line 50 says "write into the
  ticket file: Dependencies" — a `## Dependencies` section. The
  current Plane body does not specify how the dependency list is
  written into `description_html` in Plane mode. Two interpretations:
  (a) the investigator subagent writes a `<h3>Dependencies</h3>`
  block, or (b) it relies on `mcp__plane__create_work_item_relation`
  + `list_work_item_relations`. The current body says "grep for
  ticket identifiers in 'depends on' / 'blocked by' prose" plus
  "native `work_item_relations`" — both. The exact format is not
  pinned.
- Hub-file threshold (3+ tickets) is hard-coded. No project-level
  override.
- `--sequential` mode (archive line 442) bypasses dependency detection
  and parallel investigation. Useful for projects with flaky tests
  but loses the wave-detection benefit.
- The chain re-investigates between waves but does NOT re-investigate
  on `--sequential`. Mid-chain feedback is lost in `--sequential`.
- `--ship` deploys per-ticket sequentially; in projects with a real
  deploy step (Cloudflare Worker, etc.), this means N deploys. There's
  no batched-deploy mode.
- The "preview rollup" Step A (archive line 254) creates a scratch
  branch merging all successful ticket branches. Conflicts are not
  handled — the body says "create a scratch branch" with no
  conflict-resolution path. In conflict, the user falls back to per-
  ticket previews manually.

---

## /ticket-batch

**Status:** Partial. Plane path summary; Markdown path archived.
Subsumed by `/ticket-chain` for most use cases (current command body
line 8: "Prefer `/ticket-chain` for most use cases").

Body: [commands/ticket-batch.md](../../commands/ticket-batch.md). 87 lines.
Archive: [archive-commands/ticket-batch.md](../../archive-commands/ticket-batch.md).

### Differences from chain

`/ticket-batch` runs investigate → auto-approve → implement → preview
on multiple tickets in parallel worktrees, but **without dependency
detection**. No wave coordination. No re-investigation between waves.
Pre-implement conflict check is static (line 44): parse Implementation
Plan file paths, intersect pairwise, warn on overlaps but do not
block.

### Phases (Plane summary)

1. Pre-flight (line 26): load configs, clean tree, determine main.
2. Phase 0 (line 32): auto-reap.
3. Phase 1 (line 36): resolve set; explicit IDs in Backlog (will
   investigate then implement) or Ready (skip to implement); no IDs
   = all Backlog.
4. Phase 2 (line 44): pre-implement conflict check.
5. Phase 3-7 (line 48): match markdown logic. Plane-specific:
   - Per-ticket state transitions through `update_work_item`.
   - `[preview]` URL comment per ticket.
   - Description writes are read-modify-write.

### Loose ends

- The body explicitly recommends `/ticket-chain` over `/ticket-batch`
  (line 8). `/ticket-batch` exists for backward compatibility.
- `--mode=auto|rollup|individual` is per-call; conflicts with
  `Preview mode` in `ticket-config.md` are resolved by the call-time
  flag winning, but this isn't documented.

---

## /op-scaffold and /op-run — multi-plan operations

**Status:**
- `/op-scaffold` — Functional.
- `/op-run` — Functional in main session; the spawned `operation-worker`
  subagent works. The `operation-task-lead` and `operation-conductor`
  agents are **Aspirational** — `commands/op-run.md:7-8` documents
  the harness limitation that strips `Agent` from spawned subagents,
  so the original three-tier dispatch is non-functional. The main
  session inlines those procedures.

Bodies:
- [commands/op-scaffold.md](../../commands/op-scaffold.md). 475 lines.
- [commands/op-run.md](../../commands/op-run.md). 286 lines.
- [agents/operation-worker.md](../../agents/operation-worker.md). 153 lines. **Functional** subagent.
- [agents/operation-task-lead.md](../../agents/operation-task-lead.md). 247 lines. **Aspirational** — reference body cited by op-run.md via heading-anchor URLs.
- [agents/operation-conductor.md](../../agents/operation-conductor.md). 309 lines. **Aspirational** — same.
- [operation-templates/META_PROMPT_FOR_PLAN_OPUS.md](../../operation-templates/META_PROMPT_FOR_PLAN_OPUS.md) — copy-paste artifact for an external Opus session that converts a brain dump into a master plan in the format `/op-scaffold` accepts.

### When to use

For work too large for a single ticket — a multi-plan refactor, a
phased rewrite, a coordinated cross-cutting cleanup. Tickets are too
small. Operations are bounded — they end at clean local commits on
the current branch (no push, no merge, no deploy at op level —
[commands/op-run.md:107](../../commands/op-run.md)).

### /op-scaffold input (line 14)

A path to a master plan markdown file. Plan format spec at
[commands/op-scaffold.md:25-156](../../commands/op-scaffold.md):

```
# Operation: <slug>          ← lowercase kebab-case, ≤40 chars
<one-paragraph framing>

## Why this exists
<diagnosis, cost of not doing, what changes after>

## Dispatch order            ← multi-plan path; absent for flat single-plan
| Plan | Name | Depends on | Effort | Parallel-safe with |

## Plan A: <Plan Name>       ← per-row in dispatch table
### Goal
### Briefs
| # | Slug | One-line intent | Depends on | Files touched |
### Briefs — detail
#### Brief 01: <slug>
**Goal.** **Inputs.** **Outputs.** **Acceptance criteria.** **Verification.** **Notes / gotchas.** **Out of scope.**

## What done looks like      ← required, at end of file
```bash
<authoritative commands — npm run build, npm test, rg patterns>
```

`## What done looks like`'s bash block is the **load-bearing op-level
command set** (line 130 of scaffold). The scaffolder PREPENDS it
verbatim to every brief's Verification block at expansion time. So
brief verification, plan-level verification, and operation-level
verification all run the same gate.

### Validation (lines 158–215)

**Hard rejects** (line 165): refuse to scaffold; print all gaps; exit.
No "scaffold anyway" path. Eight gates:

1. Top section format.
2. Multi-plan completeness.
3. Flat single-plan layout.
4. `## What done looks like` present.
5. Dispatch graph integrity (no cycles; deps reference plan IDs in
   table).
6. Per-brief sections present (Goal/Inputs/Outputs/Acceptance/Verification).
7. Op-level commands present (executable bash, not prose).
8. No placeholder verification commands (`<...>`, `# replace`,
   `# TODO`, `<your-`, `<path-to-`).
9. UI briefs have automated verification or escape-hatch (line 175):
   any brief whose Goal/Outputs/Files-touched mention `.tsx`/`.jsx`/
   `.vue`/`.svelte`/`.css`/`.scss`/`.html`/webview/canvas/render/etc.
   must include in **acceptance criteria** an automated verification
   of the rendered surface OR a manual smoke step + tracker ticket
   ID. The acceptance list is the contract — Verification block /
   Notes / "implied by other criteria" do NOT satisfy.

**Soft warnings** (line 181): proceed only after human confirms.

10. Cross-brief file overlap.
11. Deletion brief lacks behavior test.

### Expansion to disk (lines 217–235)

```
docs/operations/<slug>/
  00-master.md             # the original plan, copied verbatim
  README.md                # auto-generated: overview + dispatch graph
  HANDOFF.md               # placeholder
  VERIFY.md                # placeholder (manual-eyeball checklist)
  operation-state.json     # initial state (all plans pending)
  plan-A-<slug>/
    00-conductor.md        # auto-generated from per-plan section
    01-<brief-slug>.md     # auto-generated; Verification PREPENDS op-level commands
    02-<brief-slug>.md
```

`operation-state.json` schema (line 367):

```json
{
  "operation": "<slug>",
  "started_at": null,
  "branch": "<current branch>",
  "plans": {
    "<ID>": {
      "status": "pending",
      "attempts": 0,
      "task_lead_summary": null,
      "started_at": null,
      "completed_at": null,
      "briefs": {
        "01": { "status": "pending", "residuals": [] },
        "02": { "status": "pending", "residuals": [] }
      }
    }
  },
  "rework_rounds": 0,
  "final_verification": null,
  "blocker": null,
  "completed_at": null
}
```

### /op-run pre-flight (lines 18–40)

1. Verify scaffolded operation: `00-master.md`, `README.md`,
   `operation-state.json`, at least one `00-conductor.md`.
2. Working tree check.
3. **Baseline check** (line 36): read `00-master.md`'s `## What done
   looks like` bash block, run every command. If broken, STOP. The
   same gate that brief/plan/op verification will run.
4. **Resume detection** (line 42): if state has `started_at != null`,
   any plan in-progress/blocked, or commits absent for `attempts > 0`,
   prompt: yes / no / abort.
5. **Special case** `blocker.reason == "residuals-undisposed"` (line
   50): print undisposed residuals and exit. The operator dispositions
   each via direct edit of `operation-state.json` and re-runs.
6. Confirm with user. If `total briefs > 40`, print warning about
   context exhaustion (line 110); user types `proceed-anyway`.

### Dispatch loop (lines 121–194)

Main session is the conductor + task-lead. Does **not** call `Agent({
subagent_type: "operation-conductor"})` or `operation-task-lead` —
both fail at runtime because the harness strips `Agent` from spawned
subagents (line 122–123).

For each plan in dispatch order (parallel where `Parallel-safe with`
permits):

1. Mark in-progress.
2. Read plan's `00-conductor.md`, note the parallel-dispatch policy.
3. **Brief loop in batches** (line 145):
   a. ONE message with one `Agent` block per brief in the batch:
      - `subagent_type: "operation-worker"`
      - `model: "sonnet"`
      - prompt built from worker dispatch template at
        `~/.claude/agents/operation-task-lead.md#worker-dispatch-prompt-template`
      - `run_in_background: false` — synchronous results required.
   b. Wait for all workers in the batch.
   c. **Verify per worker** (line 156): `git status --short`,
      `git diff --stat`, `git diff <files-from-brief>`, then run
      every command from the brief's Verification block in order, top
      to bottom. The block already includes the op-level command set
      (op-scaffold prepended it). No substitutes (e.g.
      `tsc --noEmit` for `npm run build`).
   d. **Dispose residuals** (line 164): three options —
      - `fold-in` (rework, counts toward 3-attempt cap)
      - `follow-up` (open ticket via `/ticket-new`; default when in
        doubt)
      - `accept-with-justification` (recorded in HANDOFF "Known
        limitations")

      Update `operation-state.json` brief's residuals array with
      `{ description, disposition, ticket_id_or_brief_id?,
      justification? }`.
   e. **Approve** (line 171): every Acceptance checkbox passes,
      every Verification command passes, diff contains only files in
      the brief's Outputs list, every residual has a recorded
      disposition.
   f. **Rework** (line 173): up to 3 attempts per brief. After 3
      failures, STOP, set `plans.<ID>.status = "blocked"`, set
      top-level `blocker`, prowl priority=1.
   g. **Commit** (line 175): stage only Outputs files. Message:
      `<operation-slug> [plan-<ID>] brief NN: <one-line summary>`.
      No Claude branding, no Co-Authored-By trailers.
4. Plan-level verification: re-run plan's `00-conductor.md`'s
   Plan-level verification block (which already includes op-level
   commands).
5. Advance.

### Operation-level verification (line 196)

After every plan complete: re-run `00-master.md`'s `## What done
looks like` at the operation's tip commit (HEAD). The last plan's
pass does NOT certify the operation — a plan that passed at HEAD~5
may break at HEAD because of later plans' commits. Mandatory.

### Residual-completion gate (line 206)

Walk every brief's `residuals` array. If ANY residual lacks
`disposition`, the operation is `blocked: residuals-undisposed`:
- Set top-level `blocker: { reason: "residuals-undisposed", details:
  [...] }`.
- Do NOT write HANDOFF.md or VERIFY.md.
- Prowl priority=1.

Disposed residuals (including `accept-with-justification`) do NOT
block; they flow into HANDOFF.md.

### Finalize (line 216)

1. **Write `VERIFY.md`** — manual-eyeball handoff. One section per
   UI-touching brief: what landed in user-facing terms, where to look
   (dev-server steps + URL), what to confirm (acceptance restated),
   any manual smoke step + ticket reference. If no UI brief, write
   the explicit empty-state line: "No human verification required for
   this operation."
2. **Write `HANDOFF.md`** — full report with timestamps, "What
   landed" per plan, verification output paste, deviations, commits
   in order, "Known limitations" (one bullet per
   accept-with-justification residual), "Follow-up tickets opened"
   (one per follow-up disposition), "Manual verification handoff"
   link to VERIFY.md, "Next steps", and a verbatim **Run mode line**
   (line 230): `Run mode: Main-session-as-conductor — main session
   played conductor + task-lead, dispatched operation-worker (Sonnet)
   subagents per brief.`
3. Update `operation-state.json` with `completed_at` +
   `final_verification`.
4. Send Prowl using API key from `~/.claude/CLAUDE.md` (extracted at
   runtime — never hardcoded). On failure, print curl command to
   transcript so user can resend manually.

### Edge cases (lines 267–275)

| Edge | Behavior |
|---|---|
| Dirty git mid-operation | STOP, set blocker, prowl priority=1; no auto-discard |
| Worker dispatch harness error | Retry once, then STOP |
| Worker LLM failure | Retry once, then STOP |
| Prowl call fails | Non-fatal; print full curl to transcript; continue |
| Rework cap hit on a brief | STOP, set blocker, prowl priority=1 |
| Baseline breaks mid-operation (non-operation source) | STOP, prowl priority=1 |
| Context exhaustion warning | Update state, write partial HANDOFF, prowl priority=1 with `event=Operation paused (context)` |

### Loose ends

- Heading-anchor citations (CHANGELOG line 47): `op-run.md` cites
  `agents/operation-task-lead.md` and `agents/operation-conductor.md`
  via heading-slug URLs (e.g.
  `#worker-dispatch-prompt-template`). Renaming any cited heading
  silently breaks the citation. The CHANGELOG explicitly calls this
  out as known fragility.
- Three-tier dispatch is dead. The `operation-conductor` and
  `operation-task-lead` agents exist as reference bodies (their
  `tools:` frontmatter declares `Agent` which they cannot actually
  use). The non-leaf hierarchy was originally designed; the harness
  strip on `Agent` neutered it. The `/op-run` body inlines the
  procedure instead. README.md line 94 documents this.
- Operations end at clean local commits — no push, no merge, no
  deploy. The handoff to the user is HANDOFF.md + VERIFY.md. There's
  no auto-promotion path "operation-complete → ticket(s) created" or
  "operation-complete → PR opened".
- Worker dispatch is synchronous (`run_in_background: false`). Long
  parallel batches block the main session for the slowest worker.
  No timeout enumeration.
- The `claude-cli is load-bearing` memory cited at line 269: workers
  must not propose direct-API workarounds even if `claude-cli` errors.
  Repair the pathway, never route around it.
- `agents/` directory was added recently (CHANGELOG: "Operation
  workflow"). It's the first user-level agents in claude-config.

## Composition with TravelAgent

The TravelAgent extension launches `/ticket-chain` (or `/ticket-{verb}`
for single tickets) by either typing into a VS Code chat panel or
spawning a Claude CLI terminal —
[extension/src/actions/ticketActions.ts:69-152](../../extension/src/actions/ticketActions.ts).

Specifically:
- For a single ticket: `claude /ticket-{investigate,approve,ship,review,preview} {identifier}`.
- For a batch (Array): `claude /ticket-chain {identifier1} {identifier2} ...`.
- Optional `--model {modelId}` override (terminal target only).

The extension does **not** invoke `/op-scaffold` or `/op-run`. Those
are user-driven only. Operations are a separate orchestration tier
that does not interact with the TravelAgent extension.

The extension also does **not** post fulfillment records back to
throughline-v2 via `POST /api/projects/:id/fulfillments`. That is a
consumer hook named in the throughline-v2 contract as "TravelAgent's
coordinator (or future agents)" — and as of this audit, no
claude-config slash command implements that POST either. See
[06-extension-and-external-contracts.md](06-extension-and-external-contracts.md).
