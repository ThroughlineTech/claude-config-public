# brief-templates/

Templates that `/ticket-delegate` fills in to generate self-contained phase briefs. The briefs are the contract between Claude Code (the orchestrator) and any other agent (the executor) — they're the reason cross-model delegation works without any API coupling.

## Files in this directory

| File | Phase | What the executing agent does |
|---|---|---|
| `investigate.md` | `investigate` | Explore the codebase, write Investigation + Proposed Solution + Implementation Plan |
| `implement.md` | `implement` | On the feature branch, implement the plan, add tests, commit, push |
| `review.md` | `review` | Read the diff, write a human Verification Checklist |
| `verify-investigate.md` | `verify investigate` | Peer-review another agent's investigation |
| `verify-implement.md` | `verify implement` | Peer-review the diff against the implementation plan |
| `verify-review.md` | `verify review` | Peer-review the verification checklist for completeness |

## How templates are used

1. You run `/ticket-delegate TKT-005 implement` in Claude Code
2. `/ticket-delegate` reads `brief-templates/implement.md`
3. It fills in placeholders (`{ID}`, `{TITLE}`, `{IMPLEMENTATION_PLAN}`, `{RELEVANT_FILES}`, `{TEST_CMD}`, `{BUILD_CMD}`, etc.) with values from the ticket file and `.claude/ticket-config.md`
4. It writes the result to `{project}/tickets/TKT-005.implement.brief.md`
5. You open Copilot Chat with your chosen model, run `/run-brief tickets/TKT-005.implement.brief.md`
6. The executing agent reads the brief and follows its instructions

## Editing a template

Just edit the file. Templates are symlinked into `~/.claude/brief-templates/` by `install.sh`, and `/ticket-delegate` reads them from there. Edits are live immediately.

```bash
vi brief-templates/implement.md     # or whichever
git add brief-templates/implement.md
git commit -m "improve implement template: require test count in summary"
git push
```

On other machines, `git pull` is enough — no `install.sh` re-run needed.

## Placeholder reference

When writing or editing templates, you can use these placeholders. `/ticket-delegate` will fill them in:

| Placeholder | Value |
|---|---|
| `{ID}` | Ticket ID (e.g. `TKT-005`) |
| `{TITLE}` | Ticket title from frontmatter |
| `{TYPE}` | `bug`, `feature`, or `enhancement` |
| `{DESCRIPTION}` | Ticket Description section |
| `{ACCEPTANCE_CRITERIA}` | Ticket Acceptance Criteria section |
| `{INVESTIGATION}` | Ticket Investigation section (for verify-investigate and later phases) |
| `{PROPOSED_SOLUTION}` | Ticket Proposed Solution section |
| `{IMPLEMENTATION_PLAN}` | Ticket Implementation Plan section |
| `{FILES_CHANGED}` | Ticket Files Changed section (for review and verify-implement) |
| `{TEST_REPORT}` | Ticket Test Report section |
| `{VERIFICATION_CHECKLIST}` | Ticket Verification Checklist section (for verify-review) |
| `{PROJECT_RULES}` | Relevant lines excerpted from the project's `CLAUDE.md` |
| `{RELEVANT_FILES}` | Bullet list of files to read, with one-line descriptions |
| `{TEST_CMD}` | Test command from `.claude/ticket-config.md` |
| `{BUILD_CMD}` | Build command from `.claude/ticket-config.md` |
| `{LINT_CMD}` | Lint command from `.claude/ticket-config.md` |
| `{DEPLOY_CMD}` | Deploy command from `.claude/ticket-config.md` |
| `{BRANCH}` | Feature branch name (for implement phase) |
| `{DIFF_SUMMARY}` | `git diff main...{branch} --stat` output |
| `{FULL_DIFF}` | Full diff for verify-implement |
| `{TICKET_PATH}` | Absolute path to the ticket file |
| `{TICKETS_DIR}` | Tickets directory from `.claude/ticket-config.md` |
| `{TARGET_PHASE}` | For verify phases: which phase is being reviewed |

Templates don't have to use every placeholder. Use what's relevant for the phase.

## Adding a new brief template

If you invent a new phase that doesn't fit the existing templates:

1. Create `brief-templates/{phase-tag}.md` following the structure of an existing template
2. Update `commands/ticket-delegate.md` to:
   - Add the new phase to the valid phases list
   - Add its preconditions to the phase-specific matrix (required current status, new status after delegate)
   - Add any phase-specific context gathering in the Steps section
3. Commit, push, pull on other machines

The template file is the behavior — `/ticket-delegate` just reads and substitutes, so your template fully defines what the delegated agent does.

## Template structure (what every template has)

Every template includes these sections in order, with slight phase-specific variation:

1. **Header for the human** — "This is a delegation brief for `{ID}` (`{phase}`). Run it in Copilot with `/run-brief`. When done, come back with `/ticket-collect`."
2. **Your role** — what the executing agent is playing
3. **Ticket context** — ID, title, description, acceptance criteria
4. **Project rules** — inlined from the project's CLAUDE.md
5. **Files to read first** — explicit bullet list
6. **Previous phase output** (for verify phases) — the section being reviewed
7. **What to do** — the actual instructions
8. **Where to write output** — which section of the ticket file
9. **Hard rules** — do-nots
10. **When done** — the exact output format the agent should produce

Keep templates under ~400 lines each. Briefs need to fit in the executing model's context window; overly long templates produce briefs that are hard for smaller-context models to handle.

## For the full delegation flow

See [../docs/03-delegation.md](../docs/03-delegation.md).
