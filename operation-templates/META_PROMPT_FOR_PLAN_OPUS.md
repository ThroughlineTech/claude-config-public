# Meta-prompt for plan-generation Opus

Copy the block below into a fresh Opus session (claude.ai, Console, wherever) and paste your raw idea / brain-dump after it. The Opus output will be a plan in the exact format `/op-scaffold` expects, ready to be saved and fed back into Claude Code.

The meta-prompt deliberately:
- Forces the dispatch table format
- Forces per-brief Goal/Inputs/Outputs/Acceptance/Verification/Notes/Out-of-scope
- Pushes Opus to think about parallelism (which briefs touch the same files)
- Pushes Opus to declare the brief dependency graph explicitly
- Forces a "What done looks like" integration check at the operation level
- Tells Opus NOT to ask clarifying questions (you'll iterate on the output yourself)

---

## The meta-prompt (copy from here ↓↓↓)

```
You are generating a plan for an autonomous multi-agent build system. Your output will be parsed and expanded by another agent, which will dispatch Opus task-leads (one per plan you define) and Sonnet workers (one per brief you define). Format precision matters more than prose quality. Follow the structure below verbatim — the parser is strict.

After this prompt I will paste a raw idea / brain dump. Convert it into a runnable plan.

────────────────────────────────────────────────
REQUIRED OUTPUT STRUCTURE
────────────────────────────────────────────────

# Operation: <kebab-case-slug>

<one-paragraph framing — what this operation does, why now, what changes after>

## Why this exists

<1–4 paragraphs of context: the diagnosis (what's wrong today, with concrete evidence — latencies, costs, failure modes), the cost of not doing it, what the world looks like after. This section is for the human reviewer; be concrete with numbers when the brain-dump gives you any.>

## Dispatch order

| Plan | Name | Depends on | Effort | Parallel-safe with |
|------|------|------------|--------|---------------------|
| A    | <name>     | —              | N-M days | — |
| A2   | <name>     | A complete     | N-M days | — |
| B    | <name>     | A2 complete    | N-M days | — |
| ...  | ...        | ...            | ...      | ... |

Rules:
- Plan IDs are short: A, A2, B, C, D. One letter + optional digit.
- "Depends on" must reference plans that exist in this same table, or "—".
- "Parallel-safe with" lists plan IDs this plan can run alongside. Only fill this in when you're confident the two plans don't touch overlapping files. If in doubt, leave "—" — the executor will run sequentially.
- If the work is genuinely one plan, include just one row and skip per-plan sections — the parser will handle a flat single-plan layout.

## Plan A: <Plan Name>

### Goal

<one paragraph — what this plan delivers, what changes after, what stays unchanged>

### Briefs

| # | Slug | One-line intent | Depends on | Files touched (rough) |
|---|------|-----------------|------------|----------------------|
| 01 | <kebab-slug> | <intent>   | —     | <paths>             |
| 02 | <kebab-slug> | <intent>   | 01    | <paths>             |
| 03 | <kebab-slug> | <intent>   | 01    | <paths>             |
| 04 | <kebab-slug> | <intent>   | 02,03 | <paths>             |

Rules:
- "Depends on" lists brief IDs within THIS plan only.
- "Files touched" is rough — the executor uses it to detect which briefs can run in parallel safely (briefs touching the same file are serialized).
- Aim for briefs of 50–500 lines of code change each. Smaller is fine. Larger means split it.

### Briefs — detail

#### Brief 01: <slug>

**Goal.** <1–2 sentences of what this brief delivers>

**Inputs.** Files the worker reads (full paths). Reference docs (full paths). Context the worker needs that isn't in the brief itself.

**Outputs.** Files the worker creates or edits, with paths. One bullet per file. Be exact — anything not on this list is OUT of scope for this brief.

**Acceptance criteria.**
- [ ] <concrete checkable thing — e.g., a new exported type exists>
- [ ] <a test passes — name the test or grep for the assertion>
- [ ] <a grep returns the expected result>

**Verification.** Bash commands the task-lead runs to confirm. Each command must have an inline expected result. List ONLY brief-specific checks — the scaffolder auto-prepends the operation-level command set (from `## What done looks like` below) at expansion time, so do not repeat `npm run build` or `npm test` here unless this brief has a more specific invocation (e.g., `npm test -- src/services/cis-extractor.test.ts`).

```bash
npm test -- src/services/cis-extractor.test.ts       # must pass; expect 5 tests
rg 'CISExtractor' src/providers/interfaces.ts        # must return ≥1 hit
rg 'TODO|console\.log' src/services/cis-extractor.ts # must return zero hits
```

**Notes / gotchas.** Anything subtle the worker might miss. Cross-references to other briefs. Memory'd preferences from CLAUDE.md or feedback memory if relevant.

**Out of scope.** Things that look like they belong here but don't. Be explicit — workers will scope-creep otherwise.

#### Brief 02: <slug>
... (same shape, repeat for every brief in the plan) ...

────────────────────────────────────────────────
(Repeat the "## Plan X" section for every plan in the dispatch table.)
────────────────────────────────────────────────

## What done looks like

This block has TWO required parts. The scaffolder rejects plans whose "What done looks like" has no executable bash block — it needs commands to prepend to every brief's verification.

**Part 1: executable command set (required).** A `bash` fenced block. These commands are the gate at every level (brief, plan, operation). Pick the AUTHORITATIVE paths — if the project has both `tsc --noEmit` (root convenience) and `tsc -b` (project-aware via build), use `npm run build`. The build is the lowest common denominator, NOT typecheck. A brief that passes `tsc --noEmit` but fails `npm run build` will not catch the failure until the very end.

```bash
npm run build       # must pass — authoritative typecheck path
npm test            # must pass
rg '<old-pattern>' src/   # must return zero hits — proves the pattern is gone
```

**Part 2: narrative integration checks (optional).** For things a human reads in HANDOFF.md or runs once at the end. Not gating, not auto-prepended.

1. <integration test that exercises the new end-to-end path>
2. <a smoke check the conductor can run from the command line>
3. <any cleanup criteria — dead code removed, deprecated flags gone>

────────────────────────────────────────────────
RULES YOU MUST FOLLOW
────────────────────────────────────────────────

1. Output ONLY the plan markdown. No preamble, no "Here's your plan:", no closing remarks. The first character of your response must be `#`.

2. Do NOT ask clarifying questions. If the brain-dump is ambiguous, make a defensible choice and add a one-line "Notes / gotchas" entry on the affected brief explaining the assumption. The human will fix it on review.

3. Slug rule: lowercase kebab-case, no spaces, no underscores, ≤30 chars. The operation slug at the top is ≤40 chars.

4. Brief size: aim for one focused change per brief. If a brief description grows past ~30 lines of detail, split it. The executor's worker is Sonnet — it does best with tight scope.

5. Dependency declarations matter. The executor parallelizes wherever the dependency table allows. Be honest about deps — over-declaring serializes too much, under-declaring causes merge conflicts.

6. Verification commands must be REAL commands that work in this codebase, runnable as written. NO placeholders (`<...>`, `# replace this with...`, example slugs). The scaffolder rejects any brief whose verification block contains placeholder markers. If you don't know the exact command, write the command you'd want to exist and add a "Notes" entry flagging it for human verification — but do NOT leave a placeholder in the verification block itself.

7. Acceptance criteria must be CHECKABLE AND must satisfy these rules (the scaffolder enforces some; the rest are author discipline):

   **a. Drive the real path, not a stand-in.** If a criterion is "function/feature X works," the verifying test must invoke X with its real signature against the real implementation surface. Tests that drive a stub, mock, fake, or in-memory adapter the brief itself controls do NOT satisfy this criterion. If the test surface unavoidably stubs the function under test, include a separate verification command that exercises the real path (a build, a project-aware type-check, an integration test, or equivalent).

   **b. Behavior tests for code-deletion work.** If a brief removes a code path, retires a feature, or deletes a function/module, acceptance MUST include at least one behavior test that drives a representative input through the system and asserts the deleted behavior does not manifest. Symbol-grep alone is insufficient — the symbol may disappear from source but the behavior may still fire because instructions, prompts, or callers in adjacent files preserved it.

   **c. Automated UI verification is mandatory.** If a brief produces or modifies user-visible UI (DOM, canvas, CLI output formatting, log structure, generated docs, terminal UI), acceptance MUST include at least one automated verification of the rendered surface (integration test, snapshot test, visual-regression test, screenshot diff, headless-browser DOM assertion). If automated UI testing is genuinely not yet possible in this project, cite a tracker ticket ID for adding it AND fall back to a manual smoke step. The ticket reference is the justification; "I didn't feel like writing a test" is not.

   **d. Cross-brief invariant ownership.** When multiple briefs touch the same file, each brief's acceptance describes only its own contribution. File-level invariants ("no remaining imports of Y", "no callers of removed function Z") belong on the LAST brief to touch that file in the dispatch order, OR on the operation's `## What done looks like` if no single brief is clearly last. Do NOT put "no remaining imports of X" on brief 01 if brief 03 also touches the file — the worker won't have introduced the violation yet.

   "Code is clean" is not checkable. "rg 'TODO' src/services/X.ts returns zero hits" is checkable.

8. Do NOT include sections like "Risks," "Future work," "Background reading" — they're noise to the parser. If the brain-dump asks for them, drop them and move on.

9. Output one operation. If the brain-dump describes multiple unrelated efforts, pick the dominant one and add a brief "Notes" line at the top of `## Why this exists` mentioning the others as out of scope.

10. Length is not a virtue. A tight 200-line plan with strict acceptance criteria runs better than a sprawling 1000-line plan with vague goals.

────────────────────────────────────────────────
THE BRAIN-DUMP STARTS BELOW. CONVERT IT.
────────────────────────────────────────────────

[paste your brain-dump here]
```

---

## Tips for using this

- Drop the brain-dump in raw. The meta-prompt is forgiving — it'll restructure rambling notes, fragmentary lists, even partial diffs into the correct format.
- Run it more than once if the first plan looks off. Each run costs a few minutes; iterating on the meta-prompt's output (or feeding the output back in with "make brief 03 smaller") is fast.
- Save the result to `docs/proposals/<slug>-plan.md` then run `/op-scaffold docs/proposals/<slug>-plan.md`. The scaffolder will validate and tell you what's missing if anything.
- If you have specific constraints not captured in the meta-prompt (a particular branch name, a TKT prefix to use, a known-failing baseline test set to track by name), just append them to the brain-dump as a "Constraints" preamble. Opus will respect them.
