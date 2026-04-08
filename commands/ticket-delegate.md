---
description: Delegate a ticket phase to another agent
argument-hint: TKT-XXX {phase} [target-phase]
---

# Delegate a Ticket Phase to Another Agent

Hand off a ticket phase to another agent (e.g. Gemini in Copilot Chat) by generating a self-contained brief markdown file. The brief is the contract: any agent that can read markdown and execute code can take it from here.

## Input
Argument: `{ID} {phase} [target-phase]`

Examples:
- `/ticket-delegate TKT-005 investigate`
- `/ticket-delegate TKT-005 implement`
- `/ticket-delegate TKT-005 review`
- `/ticket-delegate TKT-005 verify investigate`
- `/ticket-delegate TKT-005 verify implement`
- `/ticket-delegate TKT-005 verify review`

## Pre-flight Checks
- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- The ticket file must exist at `{tickets-dir}/{ID}.md`. If it lives in a terminal subfolder (`shipped/`, `deferred/`, `wontfix/`), STOP and tell the user to run `/ticket-reopen {ID}` first.
- Brief templates must be available at `~/.claude/brief-templates/{phase}.md` (which is symlinked from the claude-config repo). If missing, tell the user the dotfiles install is incomplete.

## Phase-specific status preconditions

| Phase                | Required current status      | New status after delegate |
|----------------------|------------------------------|---------------------------|
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
   - For `investigate`: list relevant source dirs, prior tickets touching the same area
   - For `implement`: extract the Implementation Plan from the ticket; identify exactly which files will be touched; run `xcodebuild -list` / `npm scripts` / etc. to confirm commands
   - For `review`: get `git diff main...{branch} --stat` summary
   - For `verify {phase}`: extract the section the original phase wrote (Investigation, Files Changed + diff, Verification Checklist, etc.)

3. **For `implement` only**: create the feature branch
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

5. **Write the brief** to `{tickets-dir}/{ID}.{phase-tag}.brief.md` where phase-tag is:
   - `investigate`, `implement`, `review`
   - `verify-investigate`, `verify-implement`, `verify-review`

6. **Update the ticket file**:
   - Set `status: delegated`
   - Add a line to a new "## Delegation Log" section (create if missing) recording: timestamp, phase, brief filename. This log is how `/ticket-status` reconstructs the timeline.
   - Update `updated` date

7. **Output the next-step instructions**:
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

## Rules
- The brief file is **self-contained**. Inline relevant `CLAUDE.md` rules, inline test/build commands, list specific files to read. The agent executing the brief should not need to hunt for context.
- Briefs should be 100-500 lines typical, definitely not 5000. Embed *excerpts* of files when needed, not whole files.
- For verify briefs: include the original work being reviewed in full (so the reviewer doesn't have to re-read the source ticket).
- Never write into the ticket's primary sections (Investigation, Implementation Plan, etc.) during delegation — those get filled in later by the executing agent or `/ticket-collect`. Delegation only writes the brief and the Delegation Log.
- For `implement`: branch creation is part of delegation (consistent with `/ticket-approve`). Other phases don't touch git.
- If the user re-runs delegation for the same phase (e.g. retry), overwrite the existing brief file and append a new line to the Delegation Log.
