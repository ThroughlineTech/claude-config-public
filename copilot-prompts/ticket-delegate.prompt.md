---
mode: agent
description: Delegate one or more tickets to another agent by generating self-contained brief files
argument-hint: 'TKT-XXX [...] [phase]'
---

# Delegate Tickets to Another Agent

Hand off one or more tickets to another agent (e.g. Gemini in Copilot Chat) by generating self-contained brief markdown files. The brief is the contract: any agent that can read markdown and execute code can take it from here.

**Default behavior (no phase):** delegate the full lifecycle — investigate, implement, commit — in one shot.

**Batch delegation:** pass multiple IDs to delegate several tickets at once.

## Input

Arguments: `{ID} [...] [phase] [target-phase]`

**ID shorthand:** If an ID is a bare number (e.g., `26` or `3`), resolve it to a full ticket ID: read the ticket prefix from `.claude/ticket-config.md`, scan existing ticket files to determine zero-padding width, and expand.

Examples:
- `5` — full lifecycle, single ticket
- `10 11 12 13` — batch delegation (full lifecycle for each)
- `TKT-005 investigate` — investigation only (single ticket)
- `TKT-005 implement` — implementation only (single ticket)
- `TKT-005 review` — generate verification checklist only
- `TKT-005 verify investigate` — peer-review an existing investigation
- `TKT-005 verify implement` — peer-review an existing implementation
- `TKT-005 verify review` — peer-review an existing review

Phase-specific delegation only works with a single ticket ID. Multiple IDs without a phase = full lifecycle for each.

## Pre-flight Checks

- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- The ticket file must exist at `{tickets-dir}/{ID}.md`. If in a terminal subfolder, STOP and tell the user to `/ticket-reopen` first.
- Brief templates must be available at `~/.claude/brief-templates/{phase}.md`. If missing, tell the user the dotfiles install is incomplete.

## Phase-specific status preconditions

| Phase                | Required status              | New status after delegate |
|----------------------|------------------------------|---------------------------|
| *(none — full)*      | `open`                       | `delegated` (branch created here) |
| `investigate`        | `open`                       | `delegated`               |
| `implement`          | `proposed`                   | `delegated` (branch created here) |
| `review`             | `in-progress` or `delegated` | `delegated`               |
| `verify investigate` | `proposed`                   | `delegated`               |
| `verify implement`   | `review`                     | `delegated`               |
| `verify review`      | `review`                     | `delegated`               |

If the current status doesn't match, report it and stop.

## Steps (single ticket)

1. **Read inputs:**
   - `.claude/ticket-config.md`
   - The ticket file
   - `CLAUDE.md` if present (inline relevant rules into the brief)
   - The brief template at `~/.claude/brief-templates/{phase}.md` (or `~/.claude/brief-templates/verify-{target-phase}.md`)

2. **Gather phase-specific context:**
   - `full`: list key source locations, context docs from config
   - `investigate`: list relevant source dirs, prior tickets touching the same area
   - `implement`: extract the Implementation Plan; identify files to be touched; confirm build/test commands
   - `review`: get `git diff main...{branch} --stat`
   - `verify {phase}`: extract the section the original phase wrote

3. **For `full` or `implement`:** create the feature branch:
   - Determine main branch
   - `git checkout main && git pull`
   - `git checkout -b ticket/{lowercased-id}-{slugified-title}`
   - Update ticket: set `branch` field

4. **Fill in the brief template** by replacing placeholders:
   - `{ID}`, `{TITLE}`, `{DESCRIPTION}`, `{ACCEPTANCE_CRITERIA}`
   - `{IMPLEMENTATION_PLAN}`, `{INVESTIGATION}`, `{PROPOSED_SOLUTION}`
   - `{VERIFICATION_CHECKLIST}`
   - `{RELEVANT_FILES}` — bullet list with one-line descriptions
   - `{PROJECT_RULES}` — relevant lines from CLAUDE.md, inlined
   - `{TEST_CMD}`, `{BUILD_CMD}` — from ticket-config
   - `{BRANCH}` — feature branch name (for implement)
   - `{DIFF_SUMMARY}` — for review and verify-implement phases
   - `{TICKETS_DIR}` — from ticket-config
   - `{TARGET_PHASE}` — for verify briefs only
   - `{WORKTREE_NOTE}`, `{WORKTREE_INFO}` — for parallel batch mode

5. **Write the brief** to `{tickets-dir}/{ID}.{phase-tag}.brief.md`:
   - Phase tags: `full`, `investigate`, `implement`, `review`, `verify-investigate`, `verify-implement`, `verify-review`

6. **Update the ticket file:**
   - Set `status: delegated`
   - Add a line to `## Delegation Log` (create if missing): timestamp, phase, brief filename
   - Update `updated` date

7. **Output next-step instructions:**
   ```
   {ID} delegated for {phase}

   Brief written to: {brief path}

   Next steps:
   1. Open VS Code in this project (if not already)
   2. Open Copilot Chat, select your model (e.g. Gemini)
   3. Run: /run-brief {brief path}
   4. When the agent reports "Brief executed", come back and run:
      /ticket-collect {ID}
   ```

## Batch Delegation (multiple IDs, full lifecycle)

### Step 1: Ask execution mode

Ask:
```
Delegating {N} tickets. How do you want to run them in Copilot?

  1. Parallel — each ticket gets its own worktree + VS Code window (faster, more windows)
  2. Sequential — one at a time, same window, new chat session between each (slower, simpler)
```

### Step 2: Create branches (and worktrees for parallel)

For each ticket:
1. Create the feature branch: `ticket/{lowercased-id}-{slugified-title}`
2. Update the ticket's `branch` field
3. **Parallel mode only:** create a worktree at `.worktrees/ticket-{lowercased-id}/`. Ensure `.worktrees/` is in `.gitignore`.

### Step 3: Generate briefs

For each ticket, fill in the `full.md` brief template.

**Parallel mode:** briefs include `{WORKTREE_PATH}` pointing to the ticket's worktree.

**Sequential mode:** briefs use the main project directory.

### Step 4: Generate the batch instruction file

Write `{tickets-dir}/DELEGATE-BATCH-{YYYY-MM-DD-HHMM}.md`:

**Parallel mode:**
```markdown
# Delegation Batch — {N} tickets (parallel)

Each ticket has its own worktree. Open each path in a separate VS Code window,
then run the brief in that window's Copilot Chat. They can all run simultaneously.

1. [ ] {ID} "{title}"
       Open: `code .worktrees/ticket-{lowercased-id}`
       Run:  `/run-brief {tickets-dir}/{ID}.full.brief.md`
...

When all are done, run: /ticket-collect {all IDs space-separated}
```

**Sequential mode:**
```markdown
# Delegation Batch — {N} tickets (sequential)

Run each brief in a new Copilot Chat session (fresh context between each).

1. [ ] {ID} "{title}"
       Run: `/run-brief {tickets-dir}/{ID}.full.brief.md`
       Wait for: "Brief executed"

2. [ ] {ID} "{title}"
       Start a NEW Copilot Chat session first!
       Run: `/run-brief {tickets-dir}/{ID}.full.brief.md`
...

When all are done, run: /ticket-collect {all IDs}
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

- The brief file is **self-contained**. Inline relevant `CLAUDE.md` rules, test/build commands, specific files to read. The executing agent should not need to hunt for context.
- Briefs should be 100–500 lines typical. Embed *excerpts* of files, not whole files.
- For verify briefs: include the original work being reviewed in full.
- Never write into the ticket's primary sections during delegation. Delegation only writes the brief and the Delegation Log.
- For `implement`: branch creation is part of delegation. Other phases don't touch git.
- If the user re-runs delegation for the same phase (retry), overwrite the brief file and append a new line to the Delegation Log.

## Compatibility Notes

- All source behaviors preserved exactly. No Copilot-specific adaptations required. This command generates files for other agents to consume — it does not itself run as a parallel agent.
