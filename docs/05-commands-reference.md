# Commands Reference

Terse one-section-per-command reference. For the lifecycle and examples, see [02-ticket-workflow.md](02-ticket-workflow.md). For delegation flow, see [03-delegation.md](03-delegation.md).

All commands live in `commands/` in the repo and are symlinked into `~/.claude/commands/` by `install.sh`. They're Claude Code user-level slash commands, available in every project on every machine.

## `/ticket-install`

**Purpose**: Bootstrap a project (new or existing) to use the universal ticket workflow.

**Usage**: Run once in any project, from a Claude Code session.

**What it does**:
- Detects the stack by looking for marker files (package.json, Cargo.toml, *.xcodeproj, go.mod, pyproject.toml, etc.)
- Proposes test/build/deploy commands for the detected stack
- Verifies the repo's default branch is `main`; if it's `master`, warns and offers to rename
- Asks you to confirm via AskUserQuestion
- Creates `tickets/TEMPLATE.md` with the standard frontmatter and sections
- Creates `.claude/ticket-config.md` with stack info, commands, main branch name, and key source paths
- Appends a `## Tickets` section to the project's `CLAUDE.md` (creates the file if missing)

**Preconditions**: None. Can be run on an empty or populated project.

**Side effects**: Creates files in the current project. May rename the default branch if user approves.

## `/ticket-new "title"`

**Purpose**: Create a new ticket.

**Usage**: `/ticket-new "short description"` in any bootstrapped project.

**What it does**:
- Reads `.claude/ticket-config.md` for the tickets dir and ID prefix
- Finds the next available ticket ID
- Copies `tickets/TEMPLATE.md` to `tickets/TKT-NNN.md`
- Fills in title, type (bug/feature/enhancement), priority, description, acceptance criteria — either from the argument or by asking you
- Sets status to `open`, created/updated to today

**Preconditions**: Project must be bootstrapped (`/ticket-install` has been run).

**Side effects**: Creates one file in `tickets/`. Does not touch git.

## `/ticket-list`

**Purpose**: Show all tickets grouped by status.

**Usage**: `/ticket-list`

**What it does**: Reads all `TKT-*.md` files in the configured tickets dir, parses frontmatter, groups by status, shows a table per status with ID/title/type/priority/branch.

**Preconditions**: Tickets dir exists (or returns "no tickets yet").

**Side effects**: None — read-only.

## `/ticket-investigate TKT-NNN [TKT-MMM ...] [--in-given-order]`

**Purpose**: Explore the codebase and write a plan for one or more tickets. Multi-ticket input also produces a recommended implementation order based on what the investigations found.

**Usage**:
- `/ticket-investigate TKT-005` — single ticket (existing behavior, unchanged)
- `/ticket-investigate 1 2 5` — investigate all three sequentially, then output recommended `/ta` order
- `/ticket-investigate 1 2 5 --in-given-order` — investigate in given order, skip ordering recommendation

**Single-ticket mode**:
- Verifies ticket status is `open`
- Reads `CLAUDE.md` and `.claude/ticket-config.md` for project context
- Reads the context docs listed in `ticket-config.md`
- Explores the codebase starting from the key source locations
- Writes into the ticket: Investigation section (findings), Proposed Solution section (approach), Implementation Plan section (concrete checklist)
- Transitions status to `proposed`

**Multi-ticket mode** (2+ IDs):
- Pre-flight: locates all ticket files; stops if any are in terminal status (`shipped/`, `deferred/`, `wontfix/`)
- Investigates each ticket sequentially (full single-ticket flow per ticket); already-`proposed` tickets are not re-investigated — their existing plans are read instead
- Prints a progress summary after each ticket: `✓ TKT-001 investigated (1/3) — risk: low, files: 4`
- Post-investigation ordering analysis: reads Investigation + Implementation Plan sections from all tickets, scores by: declared dependencies → risk/blast radius → shared-file conflicts → quick-win value → ticket ID
- Outputs a recommended implementation order with one-line rationale per ticket and copy-pasteable `/ta` and `/tch` commands

**Flags**:
- `--in-given-order` — investigate in the given order; omit the ordering recommendation at the end. Bare numbers expand to full IDs using the same shorthand as single-ticket mode.

**Preconditions**: All ticket files must exist and be in non-terminal status. Project must be bootstrapped. No clean-tree or main-branch requirement.

**Side effects**: Modifies one or more ticket files (Investigation, Proposed Solution, Implementation Plan sections; status → `proposed`). Reads files in the codebase (read-only on source code). Does not create branches or worktrees.

## `/ticket-approve TKT-NNN`

**Purpose**: Create a feature branch and implement the plan.

**Usage**: `/ticket-approve TKT-005`

**What it does**:
- Verifies status is `proposed` and Implementation Plan is filled in
- Verifies working tree is clean
- Creates branch `ticket/{tkt-nnn}-{slug}` from main
- Updates ticket: branch field, status `in-progress`
- Works through the Implementation Plan item by item
- Adds tests per project conventions
- Runs test and build commands from `.claude/ticket-config.md`
- Commits with message `TKT-NNN: {title}`
- Updates ticket: Files Changed, Test Report sections, status `review`

**Preconditions**: Ticket status is `proposed`, Implementation Plan is present, working tree clean.

**Side effects**: Creates a git branch, edits source files, creates commits. Does not push.

## `/ticket-delegate TKT-NNN [...] [phase] [target-phase]`

**Purpose**: Delegate one or more tickets to another agent. Default (no phase): full lifecycle. Supports batch.

**Usage**:
- `/ticket-delegate 5` — **full lifecycle, single ticket**
- `/ticket-delegate 10 11 12 13` — **batch delegation** (full lifecycle for each; asks parallel vs. sequential)
- `/ticket-delegate TKT-005 investigate` — investigation only (single ticket)
- `/ticket-delegate TKT-005 implement` — implementation only (single ticket)
- `/ticket-delegate TKT-005 verify investigate` — peer-review an investigation

**What it does**:
- Verifies each ticket is in the right status for the requested phase
- Reads the appropriate template from `~/.claude/brief-templates/{phase}.md` (or `full.md` for no-phase)
- Fills in placeholders (ticket content, project rules from CLAUDE.md, test/build commands, relevant files)
- Writes briefs to `tickets/TKT-NNN.{phase-tag}.brief.md`
- For `full` or `implement`: creates feature branches (and worktrees for parallel batch)
- For batch: asks parallel vs. sequential, generates an instruction file (`DELEGATE-BATCH-*.md`) with run order
- Transitions status to `delegated`, appends to Delegation Log section

**Preconditions**: Phase-specific status requirement (see the command file for the matrix). Full lifecycle requires `open`.

**Side effects**: Creates/overwrites brief files. For full/implement, creates git branches. For parallel batch, creates worktrees. Updates ticket files.

## `/ticket-collect TKT-NNN [...]`

**Purpose**: Collect and review work returned from delegated tickets. Supports batch.

**Usage**:
- `/ticket-collect 5` — single ticket
- `/ticket-collect 10 11 12 13` — batch: reviews all, generates consolidated checklist

**What it does**:
- Verifies each ticket status is `delegated`
- Reads the most recent Delegation Log entry to determine which phase was delegated
- For `full` (default delegation): **Claude acts as code reviewer** — reads the investigation, reviews the full diff, checks test quality, verifies acceptance criteria. Writes a `## Delegation Review` section with verdict (`approved` / `concerns` / `rejected`)
- For batch: reviews all tickets, generates a consolidated `CHAIN-REVIEW-*.md` checklist, deploys to preview/staging
- For `implement`: reads the git diff on the feature branch, fills in Files Changed and Test Report
- For `verify`: summarizes the Peer Review section and suggests next action
- Transitions status to the appropriate next state (or stays `delegated` if review is `rejected`)

**Preconditions**: Ticket status is `delegated`.

**Side effects**: Updates ticket files. For batch, generates a review checklist file. Does not modify any source code.

## `/ticket-status TKT-NNN`

**Purpose**: Show the lifecycle timeline of a ticket (or the active set with no arg).

**Usage**:
- `/ticket-status TKT-005` — full timeline for one ticket
- `/ticket-status` — one-line summary of every non-shipped, non-closed ticket

**What it does**: Reads the ticket's frontmatter, body sections, and Delegation Log; reconstructs the phases that have been done, attributes them to agents where possible, prints a timeline with timestamps and a "Next action" line.

**Preconditions**: Ticket exists (or any tickets exist for the no-arg version).

**Side effects**: None — read-only.

## `/ticket-review TKT-NNN`

**Purpose**: Generate a human-verifiable checklist for a completed implementation.

**Usage**: `/ticket-review TKT-005`

**What it does**:
- Verifies ticket status is `review`
- Verifies the feature branch is checked out
- Reads the diff against main
- Runs automated checks (tests, build, lint, typecheck, rebase status, merge conflict detection) and records pass/fail results in an `### Automated Checks` section
- Generates a Verification Checklist (for human) section with specific, observable steps for what can't be automated
- Includes Setup, Core Functionality, Edge Cases, and Regression Checks sections
- Writes the checklist into the ticket file

**Preconditions**: Ticket status is `review`, feature branch checked out.

**Side effects**: Updates the ticket file. Runs test/build/lint commands. Does not modify source code.

## `/ticket-ship TKT-NNN`

**Purpose**: Rebase, test, merge, and (optionally) deploy a reviewed ticket.

**Usage**: `/ticket-ship TKT-005` (after human has verified via the checklist).

**What it does**:
- Verifies ticket status is `review`
- Fetches and rebases onto main (stops on conflicts — does not auto-resolve)
- Runs tests after rebase (must pass)
- Runs build after rebase (must be clean)
- Writes Regression Report section
- Checks out main, pulls latest, merges the feature branch with `--no-ff`
- Runs tests and build one more time on main (resets on failure)
- Pushes main to origin
- If a Deploy command is configured in `.claude/ticket-config.md`, runs it
- Deletes the feature branch
- Transitions status to `shipped`

**Preconditions**: Ticket status is `review`, feature branch has commits, working tree clean.

**Side effects**: Rebases, merges, pushes, optionally deploys. **This is the one command that modifies remote state.** Never force-pushes. Resets on test/build failures after merge.

## Where to look if a command isn't doing what you expect

Each command's behavior is defined in `commands/{command-name}.md`. Because the file is symlinked into `~/.claude/commands/`, you can read it directly:

```bash
cat ~/.claude/commands/ticket-investigate.md
# or
cat ~/src/claude-config/commands/ticket-investigate.md
```

Claude Code reads these files verbatim as the command definition. If you want to tweak behavior for a specific command, edit the file in the repo, commit, push, pull on other machines. No re-install needed (commands are symlinked — edits are live).
