# Cross-Model Delegation

The delegation system lets you hand a ticket to a different model entirely. The default — `/ticket-delegate 5` with no phase — delegates the **full lifecycle**: the other model investigates, implements, commits, and pushes. Claude reviews the work on collect. One handoff, one context switch.

You can also delegate individual phases if you need surgical control, but the full-lifecycle delegation is the primary workflow.

## Why this exists

Different models are better at different things. Gemini is often better at UI work; Claude is often better at architectural reasoning and tracing complex codebases. If you let Claude investigate a UI ticket, Claude's investigation shapes the implementation plan — and the model that actually does the UI work is constrained by Claude's perspective. Better to let the implementing model investigate too, so it can approach the problem its own way.

The technical problem: Claude Code can't directly invoke Gemini (no API hook from Claude Code into Copilot Chat). So we use **the filesystem as the bridge**. Claude Code generates a self-contained markdown brief; you switch tools; the other model reads the brief and executes it; you switch back; Claude Code reviews the results.

## The default: full-lifecycle delegation

```bash
/ticket-delegate 5
# Creates a branch, writes tickets/TKT-005.full.brief.md
# Status: open → delegated

# In VS Code Copilot Chat (Gemini, GPT, whatever):
/run-brief tickets/TKT-005.full.brief.md
# The model investigates, implements, tests, commits, pushes

# Back in Claude Code:
/ticket-collect 5
# Claude reviews the diff, checks quality, writes a Delegation Review
# Verdict: approved → status becomes review
# Verdict: concerns → status becomes review (with flagged issues)
# Verdict: rejected → stays delegated (blocking issues found)

# If approved:
/ticket-ship 5
```

The brief tells the other model: "this is your ticket, approach it your way." It gets the ticket description, acceptance criteria, project rules, and key source locations — but no pre-existing investigation or plan. The model does its own analysis.

On `/ticket-collect`, Claude acts as **code reviewer**: reads the investigation for soundness, reviews the full diff for quality and correctness, checks tests are meaningful, verifies acceptance criteria are met. Writes a `## Delegation Review` section with a verdict (`approved`, `concerns`, or `rejected`) and specific issues if any.

## The brief format — the contract between tools

A brief is a markdown file at `{tickets-dir}/TKT-XXX.{phase}.brief.md`. It contains everything the executing agent needs, so it can work without any conversational handoff:

- A header telling the human what this file is and how to use it
- The role the agent should play
- The ticket context (description, acceptance criteria)
- Any relevant project rules (inlined from `CLAUDE.md`)
- The specific files to read first
- The work to do, step by step
- The project's test/build/deploy commands (inlined from `.claude/ticket-config.md`)
- Hard rules (what NOT to do: don't merge, don't deploy, don't touch other tickets)
- The expected output format

Briefs are generated from templates in `brief-templates/` — one template per phase. `/ticket-delegate` reads the right template, fills in placeholders, and writes the result into the project's tickets directory.

## Delegation modes

| Phase tag | Template | What the executing agent does |
|---|---|---|
| *(none — full)* | `brief-templates/full.md` | **Full lifecycle**: investigate, implement, test, commit. Claude reviews on collect. |
| `investigate` | `brief-templates/investigate.md` | Explore the codebase, write Investigation + Proposed Solution + Implementation Plan into the ticket |
| `implement` | `brief-templates/implement.md` | On an already-created branch, implement the plan, add tests, commit, push |
| `review` | `brief-templates/review.md` | Read the diff, write a human Verification Checklist into the ticket |
| `verify investigate` | `brief-templates/verify-investigate.md` | Peer-review an existing Investigation; write a "Peer Review" section |
| `verify implement` | `brief-templates/verify-implement.md` | Peer-review the diff against the plan; write a "Peer Review" section |
| `verify review` | `brief-templates/verify-review.md` | Peer-review the Verification Checklist; write a "Peer Review" section |

Full-lifecycle delegation is the default and recommended mode. Use phase-specific delegation when you want Claude to handle some phases and another model to handle others (e.g., Claude investigates, Gemini implements).

## The Copilot-side piece

On the executing side, Copilot Chat needs to know how to read a brief. That's the `copilot-prompts/run-brief.prompt.md` file, which `install.sh` symlinks into VS Code's user prompts directory. It's a generic ~10-line prompt that says "read the file at the path the user gives you, follow its instructions exactly, output a summary when done."

Because the prompt is model-agnostic, the same `/run-brief` command works with Gemini, GPT, Claude, or whatever model is loaded in Copilot. You pick the model via Copilot's model selector; the prompt stays the same.

## The end-to-end flow

```
┌──────────────┐       ┌──────────────┐       ┌──────────────┐
│ Claude Code  │       │  tickets/    │       │ Copilot Chat │
│ (orchestrate)│ writes│  TKT-005     │ reads │  (execute    │
│              │──────▶│  .brief.md   │◀──────│   with Gemini)│
│              │       │              │       │              │
│              │       │  TKT-005.md  │◀──────│              │
│              │◀──────│  (updated)   │ writes│              │
│  /collect    │       │              │       │              │
└──────────────┘       └──────────────┘       └──────────────┘
     ↓                                                ↓
 /ticket-review                              "Brief executed,
 /ticket-ship                                 hand back with
                                              /ticket-collect"
```

Everything flows through the filesystem. Neither tool knows about the other; they just read and write the same markdown files.

## Example: full-lifecycle delegation to Gemini

You're working on `TKT-005: Redesign the project picker dropdown`. It's a UI-heavy ticket, and Gemini tends to nail these. You want Gemini to handle the whole thing — investigation, implementation, tests — and Claude to review what comes back.

```bash
# In Claude Code
/ticket-delegate 5
```

Output from Claude Code:

```
TKT-005 delegated (full lifecycle)

Brief written to: tickets/TKT-005.full.brief.md
Branch created: ticket/tkt-005-redesign-project-picker-dropdown

Next steps:
1. Open VS Code in this project
2. Open Copilot Chat, select Gemini (or your model of choice)
3. Run: /run-brief tickets/TKT-005.full.brief.md
4. When the agent reports "Brief executed", come back to Claude Code and run:
   /ticket-collect 5
```

In VS Code Copilot Chat:

1. Click "New Chat" to start a fresh conversation
2. Click the model picker, select Gemini
3. Make sure "Agent" mode is enabled (not "Ask")
4. Type: `/run-brief tickets/TKT-005.full.brief.md`

Gemini reads the brief, explores the codebase, writes its own investigation and plan, implements it, adds tests, commits, pushes. When done:

```
Brief executed: tickets/TKT-005.full.brief.md
Hand back to Claude Code with: /ticket-collect TKT-005

- Regression Risk: low
- 4 files changed, 3 commits
- 12 tests added
- All tests passing: yes
- Build clean: yes
```

Back in Claude Code:

```bash
/ticket-collect 5
```

Claude reads Gemini's investigation for soundness, reviews the full diff, checks test quality, verifies acceptance criteria are met. Writes a `## Delegation Review` into the ticket:

```
TKT-005 collected from full lifecycle

Delegation Review: approved (2 nits)

  Investigation: thorough, correctly identified the Combobox migration path
  Implementation: clean, follows project conventions
  Tests: 12 added, cover all acceptance criteria
  Nits:
    1. ProjectPicker.tsx:47 — unused import of `Fragment` (should-fix)
    2. ProjectPicker.test.tsx:89 — test name is misleading (nit)

Status: delegated → review

Next: /ticket-ship 5   (or fix the nits first)
```

If Claude had found blocking issues (failing tests, missing acceptance criteria, security problems), the verdict would be `rejected` and the status would stay at `delegated` so you can re-delegate or fix manually.

## Example: batch delegation (4 UI tickets to Gemini)

You have a batch of UI tickets and want Gemini to handle them all:

```bash
/ticket-delegate 10 11 12 13
```

Claude asks: "Parallel (4 VS Code windows) or sequential (one at a time)?" You pick parallel.

Claude creates 4 worktrees, generates 4 briefs, and writes an instruction file:

```
4 tickets delegated (full lifecycle, parallel)

Instruction file: tickets/DELEGATE-BATCH-2026-04-09-1530.md

Next steps:
  Open the instruction file and follow it.
  When all briefs are executed, run: /ticket-collect 10 11 12 13
```

You open the instruction file, follow it (open 4 VS Code windows, one per worktree, run a brief in each). When all 4 are done:

```bash
/ticket-collect 10 11 12 13
```

Claude reviews all 4 diffs, writes a Delegation Review per ticket, generates a consolidated review checklist, deploys to preview. You walk through the checklist, then ship the approved ones.

## Example: phase-specific delegation (implementation only)

If Claude has already investigated and you just want another model to implement:

```bash
/ticket-delegate 5 implement
# In Copilot Chat: /run-brief tickets/TKT-005.implement.brief.md
/ticket-collect 5
```

This is the surgical version — useful when you trust Claude's investigation but want a different model's implementation style.

## Example: peer review an investigation

You're not confident Claude Code's investigation caught everything. You want Gemini to check it before you commit.

```bash
# Claude Code already investigated; status is `proposed`
/ticket-delegate TKT-005 verify investigate
```

Output:

```
TKT-005 delegated for verify investigate (target: investigate)

Brief written to: tickets/TKT-005.verify-investigate.brief.md

Next steps:
1. Open VS Code Copilot Chat
2. Select a DIFFERENT model than the one that did the original investigation
   (if Claude Code investigated, use Gemini/GPT for the review)
3. Run: /run-brief tickets/TKT-005.verify-investigate.brief.md
4. When done, run /ticket-collect TKT-005 in Claude Code
```

In Copilot Chat with Gemini:

```
/run-brief tickets/TKT-005.verify-investigate.brief.md
```

Gemini reads:
- The ticket description and acceptance criteria
- The original Investigation / Proposed Solution / Implementation Plan
- The files the original investigator referenced

Gemini writes a new section into the ticket:

```markdown
## Peer Review (verify-investigate)
*Reviewer: Gemini via Copilot*
*Date: 2026-04-07*

### Summary
Investigation has minor gaps around edge-case handling for the empty project list.

### Verified
- File paths in ProjectPicker.tsx:42-88 match the description
- The proposed Combobox component exists in @headlessui/react and matches the API described
- Regression risks around keyboard navigation are correctly identified

### Issues found
- The Investigation doesn't mention ProjectPickerEmpty.tsx which has a special render path
  for when the user has zero projects. The proposed plan doesn't touch it, but it probably should.
- The Implementation Plan step 3 says "add keyboard nav" but doesn't specify which keys.
  WAI-ARIA combobox pattern requires specific handling for Home/End and PageUp/PageDown.

### Suggested revisions
- Add a step to the Implementation Plan to handle ProjectPickerEmpty.tsx
- Expand step 3 to specify the exact key bindings required

### Approval
- [x] Approved with minor revisions (listed above)
```

Back in Claude Code:

```bash
/ticket-collect TKT-005
```

Claude Code sees the peer review, transitions status back to `proposed`, and prints a summary of what Gemini flagged. You can now either:

1. Manually edit the Implementation Plan to incorporate the suggestions, then `/ticket-approve`
2. Re-run `/ticket-investigate` with revisions (manual — see [02-ticket-workflow.md](02-ticket-workflow.md))
3. Ignore the review and proceed with `/ticket-approve` anyway (you're the decider)

## The mental model

Two roles:

- **Implementor** (the model you pick per task) — investigates, designs, builds, tests
- **Reviewer + shipper** (Claude Code) — reviews the work, merges, deploys

Full-lifecycle delegation makes this clean: the implementor does everything creative, Claude does the quality gate and the shipping. You choose the best model per ticket based on the type of work.

For phase-specific delegation, there's also a third role:
- **Peer reviewer** (a different model than the executor) — provides a second opinion on a specific phase

## When to delegate vs. when to use `/ticket-approve` or `/ticket-chain`

| Situation | Use |
|---|---|
| UI work, frontend, design-heavy | `/ticket-delegate` → Gemini (full lifecycle) |
| Straightforward bug fix | `/ticket-approve` or `/ticket-chain` (Claude does it all) |
| Batch of backend tickets | `/ticket-chain 1 2 3 4` (Claude handles everything, review checklist when done) |
| Complex architectural change | `/ticket-approve` (Claude), then `/ticket-delegate verify implement` for a second opinion |
| Investigation feels uncertain | `/ticket-investigate`, then `/ticket-delegate verify investigate` |
| Multiple tickets, mixed types | `/ticket-chain` for the ones Claude should handle, `/ticket-delegate` for the ones another model should handle |
| Quick iteration loop | `/ticket-approve` — no delegation overhead |

Rule of thumb: **full-lifecycle delegation adds one context switch** (delegate, run brief, collect). If you know another model will do a better job on the type of work, that's worth it. If Claude would do fine, skip the delegation and use `/ticket-approve` or `/ticket-chain`.

## Hard rules the brief enforces

Every generated brief explicitly tells the executing agent:

- **Do not merge to main**
- **Do not deploy**
- **Do not change branches**
- **Do not touch files unrelated to this brief's scope**
- **Do not modify other tickets' files**

This is a guardrail: the briefs are designed so you can delegate to a model you don't fully trust and know that the worst it can do is screw up one ticket's implementation (which you can always revert). It can't ship broken code, it can't step on other work, it can't deploy. The risk is bounded.

## Watch-outs

**Briefs can go stale.** If you `git pull` while a brief is waiting to be executed, the underlying code might have changed. The brief references specific files and line numbers that may have moved. Re-run `/ticket-delegate` to regenerate the brief against the current state if this happens.

**Verify loops can go forever.** Two models can ping-pong on minor disagreements. Set a personal rule: max two verify rounds per phase. If you hit round three, make the call yourself.

**The executing agent needs "agent mode," not "ask mode."** In VS Code Copilot Chat, there's a toggle between conversational Q&A mode ("Ask") and autonomous tool-use mode ("Agent"). Briefs require Agent mode because they instruct the model to actually read files, run commands, and write code. If you're in Ask mode, the model will tell you what it *would* do instead of doing it.

**Context windows vary.** Gemini's context is huge, Claude's is big, GPT-4's is smaller. If a brief is 5000+ lines, it may not fit in the smaller models. Keep briefs compact: inline *excerpts* of files when needed, not whole files. `/ticket-delegate` tries to be reasonable about this but you may need to trim manually for very large tickets.

**Peer reviewers need the same context as the original.** If you ask Gemini to verify Claude Code's investigation, Gemini needs the same files Claude Code read. `verify-*.md` templates include this, but if you find Gemini flagging things as "missing" that are actually present, check whether the brief is including enough context. Improve the template if needed.
