# Cross-Model Delegation

The delegation system lets you hand any ticket phase to any model in any tool. Use Claude Code as the orchestrator; farm out specific phases (investigation, implementation, review, or peer review of any of those) to Gemini, GPT, or any other model via Copilot Chat.

## Why this exists

Different models are better at different things. You said early on: "Gemini is just better at some UI work." Same is true the other way — Claude is often better at architectural reasoning and tracing complex codebases. You shouldn't have to pick one tool and hope it's good at everything. You should be able to use Claude Code as your general contractor and bring in specialists for specific tasks.

The technical problem: Claude Code can't directly invoke Gemini (no API hook from Claude Code into Copilot Chat). So we use **the filesystem as the bridge**. Claude Code generates a self-contained markdown brief; you switch tools; the other model reads the brief and executes it; you switch back; Claude Code picks up the results.

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

## The six phases that can be delegated

| Phase tag | Template | What the executing agent does |
|---|---|---|
| `investigate` | `brief-templates/investigate.md` | Explore the codebase, write Investigation + Proposed Solution + Implementation Plan into the ticket |
| `implement` | `brief-templates/implement.md` | On an already-created branch, implement the plan, add tests, commit, push |
| `review` | `brief-templates/review.md` | Read the diff, write a human Verification Checklist into the ticket |
| `verify investigate` | `brief-templates/verify-investigate.md` | Peer-review an existing Investigation; write a "Peer Review" section |
| `verify implement` | `brief-templates/verify-implement.md` | Peer-review the diff against the plan; write a "Peer Review" section |
| `verify review` | `brief-templates/verify-review.md` | Peer-review the Verification Checklist; write a "Peer Review" section |

The three primary phases (`investigate`, `implement`, `review`) replace the corresponding Claude Code action. The three verify phases are additive — they layer a second opinion on top of an existing phase output.

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

## Example: delegate implementation to Gemini

You're working on `TKT-005: Redesign the project picker dropdown`. Claude Code has already investigated. You want Gemini to do the UI implementation because it's better at that.

```bash
# In Claude Code (orchestrator)
/ticket-delegate TKT-005 implement
```

Output from Claude Code:

```
TKT-005 delegated for implement

Brief written to: tickets/TKT-005.implement.brief.md
Branch created: ticket/tkt-005-redesign-project-picker-dropdown

Next steps:
1. Open VS Code in this project
2. Open Copilot Chat, select your model of choice (e.g. Gemini)
3. Run: /run-brief tickets/TKT-005.implement.brief.md
4. When Gemini reports "Brief executed", come back to Claude Code and run:
   /ticket-collect TKT-005
```

In VS Code Copilot Chat:

1. Click "New Chat" to start a fresh conversation
2. Click the model picker, select Gemini (or whatever model)
3. Make sure "Agent" mode is enabled (not "Ask")
4. Type: `/run-brief tickets/TKT-005.implement.brief.md`

Gemini reads the brief, works through the Implementation Plan, commits each step, runs tests, pushes. When done:

```
Brief executed: tickets/TKT-005.implement.brief.md
Hand back to Claude Code with: /ticket-collect TKT-005

- 4 files changed
- 2 commits made
- 12 tests added
- All tests passing: yes
- Build clean: yes
```

Back in Claude Code:

```bash
/ticket-collect TKT-005
```

Claude Code pulls the latest from the branch, reads the diff, updates the ticket's "Files Changed" and "Test Report" sections, transitions status from `delegated` to `review`. Then normal flow continues with `/ticket-review` and `/ticket-ship`.

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

Three roles, any mix of models in any of them:

- **Orchestrator** (usually Claude Code) — creates tickets, decides delegation, ships
- **Executor** (the model you pick per task) — does the specific phase work
- **Reviewer** (a different model than the executor) — checks the executor's work

You can use Claude Code for all three, or split them however you want. The "use two different models" pattern is where the peer review system earns its keep: it catches things one model alone would miss.

## When to delegate vs. when to just use `/ticket-approve`

| Situation | Use |
|---|---|
| Straightforward bug fix | `/ticket-approve` (Claude Code) |
| UI work where you know another model does better | `/ticket-delegate implement` → other model |
| Complex architectural change | `/ticket-approve`, then `/ticket-delegate verify implement` for a second opinion |
| Investigation feels uncertain | `/ticket-investigate`, then `/ticket-delegate verify investigate` |
| Pure refactor where correctness matters | Implement it in one tool, verify in the other |
| Quick iteration loop | `/ticket-approve` — no need for delegation overhead |

Rule of thumb: **delegation adds ~5 minutes of tool-switching overhead per handoff**. If the ticket is small enough that 5 minutes is material, don't delegate. If the ticket is big enough that a missed requirement costs you an hour of rework, delegation and/or verification is worth it.

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
