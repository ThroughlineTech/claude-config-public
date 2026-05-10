# Plan 3: Migrate Projects to Plane

**Goal:** Move each of Dan's active projects from markdown-based ticketing to Plane-backed ticketing, starting with the Throughline LLC website as a low-stakes pilot, then iterating through the rest.

**Intended executor:** Claude Code agent with access to each project's git repo and the Plane instance. Migration is one project at a time, with a human checkpoint between each.

**Prerequisites:**
- Plan 1 complete. Plane running.
- Plan 2 complete. All commands ported. Phase 12 end-to-end test succeeded on a throwaway repo.
- Dan has a clean working tree in every repo about to be migrated (no uncommitted work).

---

## Interview checkpoint

**Migration order (proposed, confirm or revise):**
1. Throughline LLC website (`throughlinetech.net` Loomwork/Astro site) - pilot
2. Rejog (iOS app, most active, highest value to validate against)
3. `claude-config-public` itself (dogfooding: the tool that manages the workflow uses the workflow)
4. Codenoscopy
5. Loomwork
6. Sidefire / Sidefire2
7. Johnny Solarseed
8. OpenBaseline (if active work exists; otherwise fresh Plane project, no import)

**Import scope (per project):**

1. Import active tickets only (status: open, proposed, delegated, in-progress, review)?
   
   Recommend yes. Active work continues cleanly in Plane.

2. Archive terminal tickets (shipped, deferred, wontfix) in-place in git history?
   
   Recommend yes. `git mv tickets/shipped/` into `docs/archive/tickets/shipped/`. Git history preserves them without cluttering Plane or the active tickets tree.

3. Preserve original ticket IDs (TKT-001, TKT-002, etc.) somewhere in Plane?
   
   Recommend: use the `original_id` custom field (added in Plan 2 Phase 2). Plane assigns its own sequential IDs; the `original_id` field preserves the historical reference so old commit messages and investigation notes remain traceable.

4. Import investigation notes, implementation plans, verification checklists that live inside the ticket markdown?
   
   Recommend yes. Preserve as structured sections in the Plane work item's description, or as comments. Agent decides per-ticket based on content.

**Preserved content (per project):**

5. Which git branches map to in-flight work? 
   
   Agent should scan local branches matching `ticket-*` or `tkt-*` patterns and map to the imported work items via the `original_id` field.

6. Are there any worktrees under `.worktrees/ticket-*` currently active?
   
   If yes, do not migrate those projects until those worktrees ship or are explicitly abandoned. Migration assumes a stable starting state.

**Checkpoint with Dan.** Confirm order, scope, and that each project is in a stable state before starting that project's migration.

---

## Per-project migration procedure

This procedure applies to every project. Run for the pilot (Throughline website) first, then for each project in order. After each project, pause for Dan's review before proceeding to the next.

### Step 1: Pre-flight

- `git status` in the project root: confirm clean working tree
- `git branch` and `ls .worktrees/` : capture any in-flight state
- If any active worktrees exist: abort the migration for this project. Dan finishes or abandons them first.
- `/ticket-cleanup --all`: reap any stale worktrees that can be safely removed
- Confirm the repo's remote is current: `git fetch --all`

**Output:** Pre-flight report logged to `docs/plane-migration/{project-name}-preflight.md`.

### Step 2: Inventory

- Read `.claude/ticket-config.md` and capture: preview profiles, preview mode, preview command, preview port base
- Read `tickets/` directory recursively
- Categorize tickets: active (root-level `tickets/*.md`) vs terminal (`tickets/shipped/`, `tickets/deferred/`, `tickets/wontfix/`)
- For each active ticket, parse: ID, title, type, priority, status, app, description, acceptance criteria, investigation notes, implementation plan, regression risk, delegated_to
- Produce an inventory report: counts by status, list of active tickets with summaries

**Output:** `docs/plane-migration/{project-name}-inventory.md` committed to a migration branch (`feat/migrate-to-plane`).

### Step 3: Create the Plane project

- Use `/ticket-install` (the Plan 2 version) to bootstrap the Plane project for this repo
- Project name: match repo name exactly (e.g., "rejog", "codenoscopy", "throughlinetech-site")
- Populate custom field allowed values for `app` from the project's preview profiles
- Write `.claude/plane-config.md` with: workspace URL, project ID, field mappings, preview profile carry-over
- Keep `.claude/ticket-config.md` in place for now (migration isn't final until Step 7)

**Output:** Plane project exists and is addressable by the local slash commands.

### Step 4: Import active tickets

For each active ticket:

- Create a Plane work item with:
  - Title: same as the markdown ticket
  - Description: structured as ## Description, ## Acceptance Criteria, ## Investigation (if present), ## Implementation Plan (if present), ## Notes (anything else)
  - Priority: mapped per the Plan 2 mapping
  - Status: mapped per the Plan 2 mapping
  - Custom field `original_id`: the markdown ticket ID (e.g., "TKT-014")
  - Custom field `app`: the preview profile from the markdown ticket's frontmatter
  - Custom field `regression_risk`: if present in the investigation
  - Custom field `delegated_to`: if status was `delegated`
- Attach any files referenced by the ticket's markdown (screenshots, logs, etc.) if they're in the repo
- Add a comment noting "Imported from markdown ticket {original_id} on YYYY-MM-DD"

**Output:** Every active ticket exists in Plane with its full content preserved.

### Step 5: Archive terminal tickets in git

- `git mv tickets/shipped/ docs/archive/tickets/shipped/` (and same for deferred, wontfix)
- Create `docs/archive/tickets/README.md` noting: "Historical tickets from the markdown-based workflow (2025-2026). Tickets shipped after YYYY-MM-DD are tracked in Plane."
- Commit: `archive: move terminal tickets to docs/archive/ ahead of Plane migration`

**Output:** Terminal tickets preserved in git history, no longer cluttering the active tickets tree.

### Step 6: Map in-flight branches to Plane work items

For each local branch matching the ticket naming pattern:

- Find the original ticket ID from the branch name
- Look up the corresponding Plane work item via `original_id` custom field
- Note the Plane work item URL in the branch's first commit comment (via `git notes`) so future agents can find the link
- If Plane supports branch-to-work-item auto-linking via branch name, rename local branches to include the new Plane ID (only if this doesn't break in-flight work; otherwise skip)

**Output:** Branches traceable to Plane work items.

### Step 7: Smoke test

On the migrated project:

1. `/ticket-list` - confirm active tickets appear (from Plane, not markdown)
2. `/ticket-status {original_id-derived-new-id}` - confirm one ticket's state is correct
3. `/ticket-new "Migration smoke test"` - create a new work item, confirm it lands in Plane
4. `/ticket-investigate` that test ticket, confirm investigation writes back to Plane
5. `/ticket-defer {test-id} "cleanup"` - close the smoke test
6. Confirm the project's preview profiles still work by running `/ticket-preview` on an existing in-flight ticket

**Output:** Smoke test log appended to `docs/plane-migration/{project-name}-preflight.md`.

### Step 8: Cut over

Once smoke test passes:

- Delete `.claude/ticket-config.md` (replaced by `.claude/plane-config.md`)
- Delete the now-empty `tickets/` root directory (terminal subfolders are already moved to `docs/archive/`)
- Commit: `migrate: cut over to Plane-backed ticketing`
- Push the migration branch
- Open a PR to main
- Self-merge (or Dan merges) after review

**Output:** Project is fully on Plane. `tickets/` folder no longer exists. Old config removed.

### Step 9: Per-project review with Dan

Before starting the next project:
- Walk Dan through the migrated project in the Plane UI
- Show him one or two tickets, the custom fields, the preview profile wiring
- Ask: does this feel right? Anything feel worse than the old system?
- Capture feedback. If blocking issues: stop, iterate on Plan 2 to address, then resume.

---

## Per-project specifics

### Project 1: Throughline LLC website (pilot)

Lowest-stakes project. Likely fewer than 10 active tickets. Good pilot because:
- Site is live but not mission-critical
- Changes are mostly content or minor styling
- Preview profile is probably just "Astro dev server on localhost"
- If something goes wrong, the blast radius is small

**Pilot-specific checkpoints:**
- After Step 7 (smoke test): Dan reviews with extra care. This is the first real use.
- After Step 8 (cut over): Dan spends a week working normally against Plane on this project before moving to Project 2. Catch any "works in smoke test, breaks in real use" issues here.

### Project 2: Rejog

Highest-active project. This is the real validation.
- Check for in-flight Blast feature or Bear Witness work before starting
- Preview profiles likely include iOS simulator (Sequential: true); verify that grouping and batch behavior still works under Plane
- Flashmob event scheduling may drive urgency on tickets - if Dan has a live event coming up, defer this migration until after

### Project 3: claude-config-public itself

Dogfooding. The repo that manages the workflow uses the workflow.

Special considerations:
- Tickets here are about tooling changes (new commands, bug fixes, doc updates)
- No preview profile needed (it's a config repo, not an app)
- Migration doubles as a test of whether Plane can handle a project with no runtime/preview

### Project 4: Codenoscopy

AI code review tool.
- Likely has in-flight work on cost optimization per memory
- Check preview profile (probably a web service)

### Project 5: Loomwork

Framework repo; changes propagate to downstream sites.
- Confirm no in-flight framework changes blocking downstream merges
- Preview profile is an Astro dev server

### Project 6: Sidefire / Sidefire2

If both repos exist, migrate both. Sidefire2 is the active one per memory.
- Preview profile is likely a Cloudflare Workers dev server + a PWA frontend; possibly a compound profile

### Project 7: Johnny Solarseed

Website + TOU rate calculator.
- The Vitest test suite for the calculator should survive migration unchanged (no Plane involvement)
- Preview profile probably just an Astro dev server

### Project 8: OpenBaseline

If active work exists, migrate normally. If it's still in concept phase, no import needed - just create a fresh Plane project and start using it.

---

## Cross-project concerns

### Throughline LLC umbrella views

After all projects are migrated, configure Plane workspace-level views:
- "Active across all projects" - all in-progress work, grouped by project
- "In review" - awaiting verification, grouped by project
- "Deferred" - parked items that might come back
- "This cycle" - whatever cycle/sprint is active

These views give Dan the single-pane-of-glass he didn't have with markdown-per-repo.

### Shared principles across projects

Some Throughline-wide principles may deserve Plane Pages at the workspace level rather than project level:
- Engineering standards
- AI cost management principles (from the recent cost audit work)
- "How we do pitches" playbook (from Rejog pitch refinement)

Create a Plane workspace-level Wiki section for these during or after the migration.

### Intake routing

With Plane's intake feature enabled (Plan 1 Phase 10):
- Decide which projects should have their own intake email (e.g., `rejog-intake@throughlinetech.net`) vs everything routing to a single triage queue
- For a solo operator, a single triage queue is probably simpler to start; split by project later if intake volume grows

---

## Rollback

Per project, rollback is:
- Revert the migration PR
- The old markdown workflow still lives in `commands/archive/` (per Plan 2 Phase 4)
- Terminal ticket archives are untouched (they just sit in `docs/archive/tickets/`)

Cross-project rollback (if Plan 2 itself has fatal issues discovered during migration):
- Stop migrations
- Return already-migrated projects to markdown by pulling their tickets back out of Plane (write a reverse migration script if needed; should be mostly mechanical given the `original_id` field preservation)

---

## Exit ramps

- After the pilot (Throughline website): if the week of real use surfaces fundamental problems, stop. Fix in Plan 2, re-verify, then resume.
- After Rejog: this is the "does it scale to real active development" test. If it doesn't hold up here, it won't hold up elsewhere. Stop and fix.
- Between any two projects: Dan can pause migration indefinitely. Migrated projects stay migrated; un-migrated projects keep using markdown. Dual-world dispatch from Plan 2 Phase 8 makes this safe.

---

## Deliverables at end of Plan 3

- Every active project migrated to Plane
- Every active ticket imported with full content preserved and `original_id` traceable
- Terminal tickets archived in git history per-repo
- `tickets/` directories removed from every repo
- Workspace-level views configured
- Workspace-level Wiki populated with shared principles (if done)
- Intake routing live and tested

---

## Follow-on work after Plan 3

- Deprecate the markdown-backed command code path (it's no longer used by any project) - remove from `commands/archive/`, simplify install.sh
- Consider: retire the parts of `claude-config-public` that relate to markdown ticketing, keep only the Plane-backed commands + intercom + delegation layers
- Document the migration pattern itself (for future: collaborators bringing their own projects into the workspace)
- First cycle/sprint planning in Plane once a few weeks of real usage have revealed what cadence fits Dan's actual work rhythm
