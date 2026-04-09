---
description: 'TKT-XXX [...] [phase] — delegate to another agent (default: full lifecycle, supports batch)'
argument-hint: 'TKT-XXX [...] [phase]'
---

# Delegate Tickets to Another Agent

Hand off one or more tickets to another agent (e.g. Gemini in Copilot Chat) by generating self-contained brief markdown files. The brief is the contract: any agent that can read markdown and execute code can take it from here.

**Default behavior (no phase):** delegate the full lifecycle — investigate, implement, commit — in one shot. The other model does everything its own way. Claude reviews the work on collect.

**Batch delegation:** pass multiple IDs to delegate several tickets at once. Generates one brief per ticket, creates branches (and optionally worktrees for parallel execution), and writes an instruction file with the run order.

## Input
Argument: `{ID} [...] [phase] [target-phase]`

**ID shorthand:** If an ID is a bare number (e.g., `26` or `3`), resolve it to a full ticket ID: read the ticket prefix from `.claude/ticket-config.md`, scan existing ticket files to determine the zero-padding width, and expand (e.g., `26` → `TKT-026`). Full IDs and bare numbers can be mixed freely.

Examples:
- `/ticket-delegate 5` — **full lifecycle, single ticket**
- `/ticket-delegate 10 11 12 13` — **batch delegation** (full lifecycle for each)
- `/ticket-delegate TKT-005 investigate` — investigation only (single ticket)
- `/ticket-delegate TKT-005 implement` — implementation only (single ticket)
- `/ticket-delegate TKT-005 review` — generate verification checklist only
- `/ticket-delegate TKT-005 verify investigate` — peer-review an existing investigation
- `/ticket-delegate TKT-005 verify implement` — peer-review an existing implementation
- `/ticket-delegate TKT-005 verify review` — peer-review an existing review

Phase-specific delegation only works with a single ticket ID. If multiple IDs are given without a phase, full lifecycle is assumed.

## Pre-flight Checks
- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- The ticket file must exist at `{tickets-dir}/{ID}.md`. If it lives in a terminal subfolder (`shipped/`, `deferred/`, `wontfix/`), STOP and tell the user to run `/ticket-reopen {ID}` first.
- Brief templates must be available at `~/.claude/brief-templates/{phase}.md` (which is symlinked from the claude-config repo). If missing, tell the user the dotfiles install is incomplete.

## Phase-specific status preconditions

| Phase                | Required current status      | New status after delegate |
|----------------------|------------------------------|---------------------------|
| *(none — full)*      | `open`                       | `delegated` (also: branch is created here) |
| `investigate`        | `open`                       | `delegated`               |
| `implement`          | `proposed`                   | `delegated` (also: branch is created here) |
| `review`             | `in-progress` or `delegated` (after implement collect) | `delegated` |
| `verify investigate` | `proposed`                   | `delegated` (with note: verifying investigate) |
| `verify implement`   | `review`                     | `delegated` (with note: verifying implement) |
| `verify review`      | `review`                     | `delegated` (with note: verifying review) |

If the current status doesn't match, report it and stop.

## Steps

1. **Read inputs**:
   - `.claude/ticket-config.md` (for tickets dir, key source paths, test/build/deploy commands, context docs)
   - The ticket file
   - `CLAUDE.md` if present (for project rules to inline into the brief)
   - The relevant brief template at `~/.claude/brief-templates/{phase}.md` (or `~/.claude/brief-templates/verify-{target-phase}.md` for verify phases)

2. **Gather phase-specific context**:
   - For `full` (no phase): list key source locations, context docs from ticket-config, relevant source dirs
   - For `investigate`: list relevant source dirs, prior tickets touching the same area
   - For `implement`: extract the Implementation Plan from the ticket; identify exactly which files will be touched; run `xcodebuild -list` / `npm scripts` / etc. to confirm commands
   - For `review`: get `git diff main...{branch} --stat` summary
   - For `verify {phase}`: extract the section the original phase wrote (Investigation, Files Changed + diff, Verification Checklist, etc.)

3. **For `full` or `implement`**: create the feature branch
   - Determine main branch
   - `git checkout main && git pull`
   - `git checkout -b ticket/{lowercased-id}-{slugified-title}`
   - Update ticket: set `branch` field

4. **Fill in the brief template** by replacing placeholders. Common placeholders:
   - `{ID}` — ticket ID
   - `{TITLE}` — ticket title
   - `{DESCRIPTION}`, `{ACCEPTANCE_CRITERIA}`
   - `{IMPLEMENTATION_PLAN}` — verbatim from ticket
   - `{INVESTIGATION}`, `{PROPOSED_SOLUTION}`
   - `{VERIFICATION_CHECKLIST}`
   - `{RELEVANT_FILES}` — bullet list with one-line descriptions
   - `{PROJECT_RULES}` — relevant lines from CLAUDE.md, inlined
   - `{TEST_CMD}`, `{BUILD_CMD}` — from ticket-config.md
   - `{BRANCH}` — feature branch name (for implement)
   - `{DIFF_SUMMARY}` — for review and verify-implement phases
   - `{TICKETS_DIR}` — from ticket-config.md
   - `{TARGET_PHASE}` — for verify briefs only
   - `{WORKTREE_NOTE}` — for parallel batch: ` (open the worktree at {path} first)`, empty for single/sequential
   - `{WORKTREE_INFO}` — for parallel batch: `**Worktree:** \`.worktrees/ticket-{id}/\` — open this directory in VS Code`, empty for single/sequential

5. **Write the brief** to `{tickets-dir}/{ID}.{phase-tag}.brief.md` where phase-tag is:
   - `full` (no phase argument — full lifecycle)
   - `investigate`, `implement`, `review`
   - `verify-investigate`, `verify-implement`, `verify-review`

6. **Update the ticket file**:
   - Set `status: delegated`
   - Add a line to a new "## Delegation Log" section (create if missing) recording: timestamp, phase, brief filename. This log is how `/ticket-status` reconstructs the timeline.
   - Update `updated` date

7. **Output the next-step instructions** (single ticket):
   ```
   {ID} delegated for {phase}{ if verify: " (target: {target-phase})"}

   Brief written to: {brief path}

   Next steps:
   1. Open VS Code in this project (if not already)
   2. Open Copilot Chat, select your model of choice (e.g. Gemini)
   3. Run: /run-brief {brief path}
   4. When the agent reports "Brief executed", come back to Claude Code and run:
      /ticket-collect {ID}
   ```

## Batch Delegation (multiple IDs, full lifecycle)

When multiple IDs are given without a phase argument:

### Step 1: Ask execution mode

Use AskUserQuestion to ask:

```
Delegating {N} tickets. How do you want to run them in Copilot?

  1. Parallel — each ticket gets its own worktree + VS Code window (faster, more windows)
  2. Sequential — one at a time, same window, new chat session between each (slower, simpler)
```

### Step 2: Create branches (and worktrees for parallel)

For each ticket:
1. Create the feature branch: `ticket/{lowercased-id}-{slugified-title}`
2. Update the ticket's `branch` field
3. **Parallel mode only:** create a worktree at `.worktrees/ticket-{lowercased-id}/`
   - Ensure `.worktrees/` is in `.gitignore`

### Step 3: Generate briefs

For each ticket, fill in the `full.md` brief template as described in the single-ticket steps above.

**Parallel mode:** each brief includes `{WORKTREE_PATH}` pointing to the ticket's worktree. The brief tells the agent: "Your working directory is `.worktrees/ticket-{lowercased-id}/`."

**Sequential mode:** briefs use the main project directory. Each brief tells the agent to verify it's on the correct branch before starting.

### Step 4: Generate the batch instruction file

Write `{tickets-dir}/DELEGATE-BATCH-{YYYY-MM-DD-HHMM}.md`:

**Parallel mode:**
```markdown
# Delegation Batch — {N} tickets (parallel)

Each ticket has its own worktree. Open each path in a **separate VS Code window**,
then run the brief in that window's Copilot Chat. They can all run simultaneously.

1. [ ] {ID} "{title}"
       Open: `code .worktrees/ticket-{lowercased-id}`
       Run:  `/run-brief {tickets-dir}/{ID}.full.brief.md`

2. [ ] {ID} "{title}"
       ...

When all are done, come back to Claude Code and run:
  /ticket-collect {all IDs space-separated}
```

**Sequential mode:**
```markdown
# Delegation Batch — {N} tickets (sequential)

Run each brief in a **new Copilot Chat session** (fresh context between each).
Stay in the same VS Code window — the brief handles branch switching.

1. [ ] {ID} "{title}"
       Run: `/run-brief {tickets-dir}/{ID}.full.brief.md`
       Wait for: "Brief executed"

2. [ ] {ID} "{title}"
       Start a NEW Copilot Chat session first!
       Run: `/run-brief {tickets-dir}/{ID}.full.brief.md`
       Wait for: "Brief executed"
...

When all are done, come back to Claude Code and run:
  /ticket-collect {all IDs space-separated}
```

### Step 5: Update all ticket files

For each ticket: set `status: delegated`, append to Delegation Log, update date.

### Step 6: Output summary

```
{N} tickets delegated (full lifecycle, {parallel|sequential})

Briefs written:
  {tickets-dir}/{ID1}.full.brief.md
  {tickets-dir}/{ID2}.full.brief.md
  ...

Instruction file: {tickets-dir}/DELEGATE-BATCH-{timestamp}.md

Next steps:
  Open the instruction file and follow it.
  When all briefs are executed, run: /ticket-collect {all IDs}
```

## Rules
- The brief file is **self-contained**. Inline relevant `CLAUDE.md` rules, inline test/build commands, list specific files to read. The agent executing the brief should not need to hunt for context.
- Briefs should be 100-500 lines typical, definitely not 5000. Embed *excerpts* of files when needed, not whole files.
- For verify briefs: include the original work being reviewed in full (so the reviewer doesn't have to re-read the source ticket).
- Never write into the ticket's primary sections (Investigation, Implementation Plan, etc.) during delegation — those get filled in later by the executing agent or `/ticket-collect`. Delegation only writes the brief and the Delegation Log.
- For `implement`: branch creation is part of delegation (consistent with `/ticket-approve`). Other phases don't touch git.
- If the user re-runs delegation for the same phase (e.g. retry), overwrite the existing brief file and append a new line to the Delegation Log.
