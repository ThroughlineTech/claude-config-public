---
applyTo: "**"
---

# Plan Mode Discipline

Read this before presenting a plan (via ExitPlanMode) or writing one to an on-disk plan file. Applies to any agent: Claude Code, Copilot, Gemini, GPT.

## Rules

### Anchor the scope on a named artifact
If the user points to a reference — a POC, an existing module, a ticket spec, a design doc — that artifact IS the scope. Your plan ports or adapts it. Don't invent beyond it. If parts don't port cleanly, list those specific items; don't expand elsewhere.

### Hold the plan-size budget
If the user sets a budget ("one screen", "three steps", "it's a bug fix"), hold to it. Default budget: **the plan fits on one screen, ~60 lines.** If the plan exceeds the budget, stop and ask: *"This plan is getting big. Cut scope, split into phases, or keep going?"* Don't present an over-budget plan and make the user do the cutting.

### Subtract before presenting
Before every ExitPlanMode, do one explicit pass: "what can be cut or deferred?" Plans that only accumulate are wrong. Every new item's default disposition is "follow-up ticket" unless the user explicitly folds it in.

### External feedback is parked, not absorbed
Feedback from other reviewers (Gemini, Copilot, another Claude agent, mid-plan human review) goes in a parked list. Default disposition: follow-up. Fold items in only when the user explicitly greenlights them one by one. Don't play stenographer for external AI.

### Rejected ExitPlanMode = pause, not elaborate
If the user rejects ExitPlanMode without a reason, stop editing the plan and wait. Don't add detail. Don't propose variants. Default interpretation: "I'm thinking, give me a minute" — not "needs more detail."

### Rescopes produce visible deletions
When the user rescopes mid-flow ("separate ticket", "land UX first", "defer Y"), produce a visible deletion in the plan. A verbal "got it" isn't enough — the plan artifact must shrink to match.

### Every 10 turns, summarize
Ask: *"If we stopped here, what would be built vs. what would be captured for later?"* If the built-list doesn't fit on one screen, something is wrong. This catches long conversations even when the plan file itself is still small.

### Side tasks never touch the plan file
If you need to jot intermediate findings, run an exploratory check, or handle a tangent, use a scratch file or the shell. Don't overwrite, rewrite, or bloat the canonical plan file with tangent work.

### Flag file growth past the project ceiling
If your plan pushes a file past its project size ceiling (300 lines for Throughline) — or adds to a file already past it — call it out and propose a factor-first step. Don't silently grow large files. The human decides whether to factor now, defer, or accept.

### Every plan includes a human ship gate
"Tests green" is not "shipped." Every plan must name a human verification step: who clicks what, who runs what workflow, who confirms what behavior. Automated checks alone are not a ship gate.

### Split delight from fix
If a plan bundles a bug fix with a "wow" / delight feature, split them. Different ship gates, and the delight feature deserves its own demo.

## The plan format

```
## Plan: {2-10 word title}

{One paragraph: what, why, approach.}

**Relevant files**
- path/to/file.ts — what changes

**Steps**
1. …

**Verification**
- Specific checks, including at least one manual step if UI work.

**Out of scope**
- Explicit deferrals.

---
investigated_at_sha: <SHA>
```

`Relevant files` and `investigated_at_sha` are load-bearing for downstream drift detection and conflict scheduling. Not optional.

## Anti-patterns

- Absorbing external-AI feedback wholesale instead of triaging.
- Adding an "iOS fallback" / "policy layer" / "edge case" section because it feels thorough.
- Treating rejected ExitPlanMode as a signal to add detail.
- Shipping with manual-verification checklist items unchecked.
- Growing files past the project's size ceiling without splitting.
- Pre-specifying edge cases the user hasn't asked about. Happy path first.
- Bundling "hey that was cool" delight work into a bug fix.
