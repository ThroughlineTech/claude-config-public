---
description: 'run a scaffolded operation autonomously in the current session'
argument-hint: '<path-to-operation-folder>'
---

# Run a Scaffolded Operation

You are running a scaffolded operation as the **in-session conductor**. The Claude Code harness strips the `Agent` tool from spawned subagents regardless of frontmatter, so the original three-tier dispatch chain (`conductor → task-lead → worker`) is non-functional. The main session itself plays conductor + task-lead inline and dispatches only `operation-worker` (Sonnet) subagents per brief. The session must stay open for the duration; closing it halts the run.

## Input

The argument is the path to a scaffolded operation folder. Examples:
- `/op-run docs/operations/<operation-slug>/`
- `/op-run docs/operations/auth-rewrite/`

If no argument is given, ask the user for the operation folder path.

## Pre-flight checks (the main session does these directly)

1. **Verify the folder is a scaffolded operation:**
   - `<folder>/00-master.md` exists.
   - `<folder>/README.md` exists.
   - `<folder>/operation-state.json` exists.
   - At least one `<folder>/plan-*/00-conductor.md` exists, OR `<folder>/00-conductor.md` exists for flat operations.

   If any of these are missing: STOP, tell the user the folder isn't a valid scaffolded operation, and suggest re-running `/op-scaffold`.

2. **Verify the working tree:**
   ```bash
   git status --short
   git branch --show-current
   git log --oneline -3
   ```
   Print the current branch and recent commits so the user can confirm. If there are uncommitted changes outside the operation folder AND outside any path the operation will touch (per the briefs' "Files touched" lists), STOP and ask the user whether to stash, commit, or proceed.

3. **Verify the baseline.** Read `00-master.md`'s `## What done looks like` bash block. Run every executable command in it, in order. This is the operation-level command set — the same gate every brief, plan, and the operation itself will be measured against. Running it at pre-flight catches a broken baseline before any worker spends tokens.
   ```bash
   # exactly the commands from 00-master.md "What done looks like"
   ```
   If baseline is broken, STOP and tell the user. Exception: if `00-master.md` or any `00-conductor.md` lists explicit known-baseline failures (track-by-name pattern), confirm the failing set matches that exact list — if it matches, proceed; if extra failures appear, STOP.

4. **Resume detection** — handle a previously-failed run gracefully.

   Read `<folder>/operation-state.json`. The operation needs cleanup if any of these are true:
   - `operation.started_at` is non-null.
   - Any plan has `status: "in-progress"` or `status: "blocked"`.
   - Any plan has `attempts > 0` AND `git log --oneline | grep "<operation-slug>"` returns zero commits matching the prefix.
   - Top-level `blocker` field is non-null.

   **Special case: `blocker.reason == "residuals-undisposed"`.** The operation's plans are all `complete`; only residual disposition is missing. Do NOT reset state. Print:

   ```
   Operation blocked on undisposed residuals. <count> residuals across <N> briefs.
     <plan-ID>/brief-NN: <description>
     <plan-ID>/brief-NN: <description>
     ...

   Disposition each by editing operation-state.json's plans.<ID>.briefs.<NN>.residuals[],
   adding a "disposition" field (fold-in / follow-up / accept-with-justification) to each
   entry. Then re-run /op-run to resume — finalization will pick up where it left off.
   ```

   Exit. Do NOT proceed to the dispatch loop.

   For all OTHER cleanup conditions, identify candidate dirty files. A file is a "stale partial-write" if it shows in `git status --short` AND its path matches any brief's "Files touched" list across the operation. Print:

   ```
   Operation appears to have failed mid-flight.
     Last attempt:        <started_at>
     Plans in-progress:   <list>
     Last blocker:        <blocker.summary or "(none recorded)">
     Stale partial files: <count, with paths>
     Operation commits in git log: <count>

   Reset to clean state and re-run? (yes / no / abort)
     yes:   discard the listed dirty files, reset state to pending, then proceed.
     no:    keep the dirty files; reset state only.
     abort: leave everything as-is and stop.
   ```

   On `yes`: `git checkout -- <each-stale-file>`, then rewrite `operation-state.json` so every plan is `{ status: "pending", attempts: 0, started_at: null, completed_at: null, task_lead_summary: null }` (preserve `briefs.*` map if present, set each brief to `"pending"`); set top-level `started_at: null`, `blocker: null`, `rework_rounds: 0`, `final_verification: null`, `completed_at: null`.

   On `no`: same state reset, but leave the dirty files in place. Warn the user the run will likely fail the "dirty git check" before each commit.

   On `abort`: stop and exit. Do not modify anything.

5. **Confirm with the user.**

   Read every brief file under the operation folder to count totals.

   ```
   Ready to launch operation: <slug>

   Branch:   <branch>
   Plans:    <N>  (<IDs, sequential per dispatch order>)
   Briefs:   <total>  (parallelized within each plan per the brief dep graph)
   Baseline: <green | known-failures-match>

   The operation will:
     - Be driven by the MAIN session as conductor + task-lead (this session must stay open).
     - Dispatch `operation-worker` (Sonnet) subagents per brief, in parallel batches per the conductor brief.
     - Verify each worker's output (diff + greps + brief Verification commands).
     - Auto-commit verified work to <branch>. Commit prefix: `<operation-slug> [plan-<ID>] brief NN: <summary>`.
     - Send a Prowl notification when complete or blocked.
     - NOT push, merge, or deploy.

   Proceed? (yes/no)
   ```

   If `total briefs > 40`, before this prompt also print:

   ```
   ⚠ This operation has <N> briefs. Long operations may exhaust the main session's context.
     Operations above ~30 briefs have historically run for several hours and approached
     the context limit. Consider splitting before running. Type "proceed-anyway" instead
     of "yes" to override.
   ```

   Wait for explicit `yes` (or `proceed-anyway` if the warning fired) before continuing.

## Dispatch loop — main session is the conductor + task-lead

This section is the procedure the main session executes itself. Do NOT call `Agent({subagent_type: "operation-conductor"})` or `Agent({subagent_type: "operation-task-lead"})`. Both fail at runtime because the harness strips the `Agent` tool from spawned subagents. The main session is the conductor and the task-lead.

### Initialize

- Set `operation.started_at` (ISO8601 now) in `operation-state.json`.
- Capture `git rev-parse HEAD` as `baseline.head`.
- Detect layout: if `<folder>/plan-*/00-conductor.md` exists, this is a multi-plan operation. Otherwise it's flat (treat the operation root as a single "main" plan).
- Read every plan's `00-conductor.md` and every brief file under each plan folder. Build an in-memory map of brief dependencies and "Files touched" lists.

### Plan loop (sequential per dispatch order, parallel-where-permitted)

For each plan in dispatch order (per `00-master.md`'s `## Dispatch order` table):

- Honor `Parallel-safe with` — plans listed parallel-safe with each other can run concurrently. Concretely: dispatch worker batches for two plans in parallel by issuing all batches' `Agent` calls in a single message.
- A plan is "ready" when every plan listed in its `Depends on` column has `status: "complete"` in `operation-state.json`.

**For each ready plan:**

1. **Mark in-progress.** Set `plans.<ID>.status = "in-progress"`, `plans.<ID>.started_at = now`, increment `attempts`.

2. **Read the plan's `00-conductor.md`.** Note the "Parallel dispatch policy" section — it lists the safe parallel batches.

3. **Brief loop — dispatch in batches.** For each batch listed in the plan's parallel dispatch policy:

   a. **In ONE message**, issue one `Agent` tool-use block per brief in the batch:
      - `subagent_type: "operation-worker"` (the worker is a registered subagent and works correctly — it has no `Agent` tool but doesn't need one)
      - `model: "sonnet"` (already in the worker's frontmatter; explicit here for clarity)
      - `description`: `"brief NN: <slug>"` (e.g. `"brief 03: extractor-llm-call"`)
      - `prompt`: built from the worker dispatch template at [~/.claude/agents/operation-task-lead.md → "Worker dispatch prompt template"](~/.claude/agents/operation-task-lead.md#worker-dispatch-prompt-template). Substitute the brief's path, the plan's slug, and the operation's slug.
      - `run_in_background: false` — you need synchronous results to verify before committing.

   b. **Wait for all workers in the batch to return.** Each worker reports back with files-changed, tests-run results, and grep output per the structured report format in [~/.claude/agents/operation-worker.md → "Reporting back"](~/.claude/agents/operation-worker.md#reporting-back).

   c. **For each completed worker**, verify per [~/.claude/agents/operation-task-lead.md → "3. Independently verify"](~/.claude/agents/operation-task-lead.md#3-independently-verify):
      ```bash
      git status --short                   # what actually changed
      git diff --stat                      # file count + magnitude
      git diff <files-from-brief>          # read the diff in full
      ```
      Then run **every command from the brief's Verification block**, in order, top to bottom. The block already includes the operation-level command set (op-scaffold prepended it). Do NOT substitute a faster command (e.g. `tsc --noEmit` for `npm run build`) — the brief's commands are the gate. Don't skip any.

   d. **Dispose of residuals (before approve).** Parse the worker's `Residuals:` section. If non-empty, you MUST assign every residual one of three dispositions before approving — see [~/.claude/agents/operation-task-lead.md → "4a. Dispose of residuals"](~/.claude/agents/operation-task-lead.md#4a-dispose-of-residuals-before-approving):
      - **`fold-in`** — rework the brief to address the residual. Counts toward the 3-attempt rework cap.
      - **`follow-up`** — open a tracker ticket via `/ticket-new`. Default choice when in doubt — operations are finite. Record the ticket ID.
      - **`accept-with-justification`** — record the residual + a one-line justification. Surfaces in HANDOFF.md's "Known limitations" at finalization.

      Update `operation-state.json` for the brief: append each residual to `plans.<ID>.briefs.<NN>.residuals` with shape `{ description, disposition, ticket_id_or_brief_id?, justification? }`. A residual missing `disposition` blocks operation-level completion.

   e. **Approve** if every Acceptance checkbox passes, every Verification command passes (or matches documented expected failures), the diff contains only files in the brief's "Outputs" list (creep is a rework signal), and every residual from step d has a recorded disposition.

   f. **Rework** if any check fails. Re-dispatch a fresh `operation-worker` with a focused prompt naming the specific failures (file:line, observed vs expected). **Rework cap: 3 attempts per brief.** After 3 failures, STOP this brief, set `plans.<ID>.status = "blocked"`, set top-level `blocker: { plan: "<ID>", brief: "NN", attempts: 3, last_failure: "<summary>" }`, prowl priority=1, and exit.

   g. **On approve, commit.** Stage only the explicit Outputs files for the brief. Commit message:
      ```
      <operation-slug> [plan-<ID>] brief NN: <one-line summary>

      <2-3 lines of what landed>
      ```
      No Claude branding, no `Co-Authored-By` trailers (per global CLAUDE.md). Update `briefs.<NN> = "complete"` in `operation-state.json`.

4. **Plan-level verification.** After every brief in the plan is committed, run the plan-level "What done looks like" checks from `<plan>/00-conductor.md` verbatim. The conductor brief's "Plan-level verification" block already includes the operation-level command set (op-scaffold prepended it) plus any plan-specific checks. Run them as written; do not substitute faster variants.

   ```bash
   # exactly the commands in <plan>/00-conductor.md "Plan-level verification" block
   ```

   On fail: identify the owning brief, run rework on it (counts toward its 3-cap).

   On pass: set `plans.<ID>.status = "complete"`, `plans.<ID>.completed_at = now`, `plans.<ID>.task_lead_summary = "<short summary of commits + verification output>"`.

5. **Advance.** If any other plan's deps are now satisfied, dispatch it. Otherwise wait for in-flight plans to complete, then advance.

### Operation-level verification

After every plan is `complete`:

1. Run the operation-level `## What done looks like` checks from `00-master.md`. These are integration-level, not per-plan. **Run them at the operation's tip commit (current HEAD), not against any per-plan verified state** — a plan that passed at HEAD~5 may break at HEAD because of later plans' commits. This rerun is mandatory; the last plan's pass does not certify the operation.

2. If any operation-level check fails: identify the owning plan, send a final rework round to the affected brief(s). This counts toward each brief's 3-cap.

3. When all operation-level checks pass, proceed to the residual-completion gate.

### Residual-completion gate

Before writing HANDOFF.md or VERIFY.md, walk every brief's `residuals` array in `operation-state.json`. If ANY residual lacks a `disposition` field, the operation is **blocked: residuals-undisposed**:

- Set top-level `blocker: { reason: "residuals-undisposed", details: [{ plan: "<ID>", brief: "NN", description: "..." }, ...] }`.
- Do NOT write HANDOFF.md or VERIFY.md.
- Prowl with priority=1, `event=Operation BLOCKED (undisposed residuals): <slug>`, `description=<count> residuals across <N> briefs need disposition before the operation can complete.`
- Exit. The operator can re-run after dispositioning each residual via the resume detector.

Disposed residuals (including `accept-with-justification`) do NOT block. They flow into HANDOFF.md and follow-up tickets surface in HANDOFF.md's "Follow-up tickets opened" section.

### Finalize

1. **Write `VERIFY.md`** in the operation folder per the template at [~/.claude/agents/operation-conductor.md → "VERIFY.md template"](~/.claude/agents/operation-conductor.md#verifymd-template-manual-verification-handoff). One section per UI-touching brief (per the heuristic in op-scaffold's UI-brief detection): what landed in user-facing terms, where to look (dev-server steps + URL/path), what to confirm (acceptance restated for human eyes), any manual smoke step + ticket reference from the escape-hatch path. If no brief touched UI, write the empty-state line: `No human verification required for this operation. All acceptance criteria were satisfied by automated checks at the brief, plan, and operation levels.` That line is itself an artifact — explicit assertion, not absence.

2. **Write `HANDOFF.md`** in the operation folder. Use the structure documented at [~/.claude/agents/operation-conductor.md → "HANDOFF template"](~/.claude/agents/operation-conductor.md#handoff-template):
   - Started / Completed timestamps + branch + total commits + total worker dispatches + total rework rounds.
   - "What landed" — one paragraph per plan summarizing commits and changes.
   - "Verification" — paste the output of every operation-level check (run at HEAD).
   - "Deviations from the master plan" — bullet list with file:line references.
   - "Commits in order" — `git log --oneline <baseline.head>..HEAD`.
   - "Known limitations" — one bullet per residual disposed as `accept-with-justification` (file:line + recorded justification).
   - "Follow-up tickets opened" — one bullet per residual disposed as `follow-up` (tracker ticket ID).
   - "Manual verification handoff" — link to `VERIFY.md`.
   - "Next steps" — follow-ups, deferred work, related cleanup.
   - **Run mode line** (verbatim): `Run mode: Main-session-as-conductor — main session played conductor + task-lead, dispatched operation-worker (Sonnet) subagents per brief.`

3. **Update `operation-state.json`** — set `completed_at`, `final_verification: { ...per-check results... }`.

4. **Send Prowl** using the global API key from `~/.claude/CLAUDE.md` (extracted at runtime — never hardcoded):
   ```bash
   PROWL_KEY=$(grep -oE '\b[a-f0-9]{40}\b' ~/.claude/CLAUDE.md | head -1)
   curl -s https://api.prowlapp.com/publicapi/add \
     -d "apikey=$PROWL_KEY" \
     -d "application=op-run: $(basename "$PWD")" \
     -d "event=Operation complete: <slug>" \
     -d "description=<plans> plans, <commits> commits, <rework_rounds> rework rounds. HANDOFF.md ready for review." \
     -d "priority=0"
   ```
   On block (any STOP path above): same call but `event=Operation BLOCKED: <slug>`, `priority=1`, `description=<plan, brief, attempts, last_failure_summary>`.

   If the curl fails (non-200, network error, etc.): print the curl command + payload to the transcript so the user can resend manually, write `HANDOFF.md` regardless, exit normally. Do NOT block completion on notification delivery.

5. **Final response to user (one or two sentences):** "Operation complete (or blocked). HANDOFF.md and VERIFY.md written at `<path>`. Prowl sent (or printed for manual resend). Walk VERIFY.md before merging."

## Closing message to user (immediately after they say "yes" at confirmation)

```
Operation running in this session: <slug>

Live status:  cat docs/operations/<slug>/operation-state.json
Final report: docs/operations/<slug>/HANDOFF.md (written at completion)
Branch:       <branch>

Keep this session open — closing halts the run. The Prowl will arrive when the
operation completes or blocks. The main session is the conductor; if you see
me dispatching `operation-worker` subagents, that's expected.
```

Then begin the dispatch loop. Do not exit — the run happens in this session, in this turn (and subsequent turns as workers complete).

## Edge cases — what to do when

- **Dirty git mid-operation.** Before each commit (step 3g), verify `git status --short` is a subset of the brief's Outputs. If extra files appear, STOP, set `blocker`, prowl priority=1, leave state in-progress for forensics. Do not auto-discard.
- **Worker dispatch fails** (harness error returning a tool-use error, not an LLM failure). Catch the error, retry the same dispatch ONCE, then STOP and prowl. Per memory `feedback_claude_cli_is_load_bearing`: do NOT propose direct-API workarounds.
- **Worker hits LLM failure** (timeout, 5xx, etc.). Same as above — retry once, then STOP.
- **Prowl call fails.** Non-fatal. Print the full curl invocation + intended payload to the transcript. Continue to write `HANDOFF.md`. Exit normally.
- **Rework cap hit on a brief** (3 attempts all failed). STOP, set `plans.<ID>.status = "blocked"`, set top-level `blocker`, prowl priority=1.
- **Baseline breaks mid-operation** — a typecheck or test that was green at preflight is now red, attributable to a non-operation source. STOP, prowl priority=1. Do not try to fix.
- **Context exhaustion warning** (the runtime warns about approaching context limits). Update `operation-state.json` with current progress, write a partial `HANDOFF.md` describing what got done, prowl priority=1 with `event=Operation paused (context): <slug>`. The user can resume via the resume detector.

## Things you must not do

- Don't dispatch `operation-conductor` or `operation-task-lead` as subagents. They will spawn without `Agent` and exit immediately.
- Don't dispatch the main session's loop with `run_in_background: true`. The orchestration lives in this session; it cannot be detached.
- Don't push, merge, deploy, or run `npm run deploy` as part of this command. Operations end at clean local commits on the current branch.
- Don't modify briefs to make them easier to satisfy. If a brief is wrong, STOP and prowl Dan.
- Don't bypass `claude-cli` if a worker reports LLM failure — repair the pathway, escalate via prowl. (Per `feedback_claude_cli_is_load_bearing`.)
- Don't summarize the operation in your final response — the summary lives in `HANDOFF.md`. Final response is one or two sentences.
- Don't poll `operation-state.json` between events — write to it at state transitions, that's it.
- Don't hardcode the Prowl API key. Always extract it from `~/.claude/CLAUDE.md` at runtime — the key string must not appear in any committed file.
