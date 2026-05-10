# Design Decisions

Non-obvious design choices in this repo, with the reasoning behind each. Read this when
you're tempted to change something and wondering "why was it done this way?" — there may
be a reason you're about to rediscover the hard way.

Date: 2026-05-09. Code-true at HEAD `7f34639`.

## 1. Cross-model delegation via briefs (not direct API calls)

**The decision**: `/ticket-delegate` writes a self-contained markdown brief file. You
manually switch to Copilot Chat, pick a model, and run the brief. The executing agent
writes results back into the ticket. You come back to Claude Code and run `/ticket-collect`.

**The alternative considered**: have Claude Code invoke Gemini directly via some API hook
so the delegation is seamless — no manual tool switching.

**Why we chose briefs**:

1. **Claude Code can't actually invoke Copilot Chat.** There's no API bridge. Even if we
   wanted the "seamless" approach, it doesn't exist with current tools.
2. **Filesystem-as-bridge is model-agnostic.** Today it's Gemini. Tomorrow it's GPT-5 or
   Claude Opus 5 or something we haven't heard of yet. The brief format doesn't care — any
   model that can read markdown and execute tool calls can execute a brief.
3. **Human-in-the-loop is a feature, not a bug.** The manual tool-switch is friction, but
   the friction is what keeps you steering per-ticket decisions ("is Gemini really better
   for this, or should Claude Code just do it?"). Automating the handoff removes that judgment.
4. **Briefs are inspectable and auditable.** You can read a brief before executing it,
   after, and six months later. The ticket accumulates the audit trail.
5. **Briefs can be executed by things other than Copilot.** Another Claude Code session,
   Aider, Cursor, or a person who reads the brief and types it out. Format is universal.

**What we gave up**: ~5 minutes of tool-switching overhead per delegation. Worth it.

## 2. Platform-split settings with jq merge (not one settings.json)

**The decision**: `settings.base.json` for universal settings, `settings.mac.json` and
`settings.windows.json` for platform-specific additions, merged at install time via jq.

**The alternative considered**: one `settings.json` with everything, or one per machine.

**Why we chose the split**:

1. **No absolute paths in synced files.** A single file with both Mac-specific and
   Windows-specific entries is confusing on both machines. The split keeps each file focused.
2. **Clean allow list.** Base is ~40 universal tools; platform files are 10–15 OS-specific
   entries each. Together comprehensible; merged manually they'd be 60+ entries with no structure.
3. **Easier to promote grants.** Mac-specific pattern → `settings.mac.json`. Universal →
   `settings.base.json`. Placement is obvious from the nature of the command.
4. **jq merge is idempotent and debuggable.** Running twice produces the same file. You can
   replicate the merge command manually to debug.

**What we gave up**: a little install complexity (the jq merge expression is not trivial).

## 3. Plans live in the repo (not local-only)

**The decision**: `plans/` is synced via git. `claude-handoff` pushes the most recent plan
under a pointer name (`_next.md`) so the other machine knows which plan to execute.

**The alternative considered**: local plans only, or shared filesystem (Dropbox, iCloud).

**Why we chose git-synced**:

1. **Git handles conflicts explicitly.** Simultaneous edits surface as a conflict you
   resolve. Dropbox would silently overwrite.
2. **Plan history becomes durable and searchable.** Grep old plans, `git blame` evolution,
   reference prior design work. Plans become a knowledge artifact, not ephemeral state.
3. **Same sync mechanism as everything else.** `git pull` gets you commands, templates,
   and plans. No second sync tool.
4. **Enabling infrastructure for cross-machine handoff.** "Build a plan on the laptop,
   execute on the always-on desktop" is the use case synced plans exist for.

**What we gave up**: plans accumulate over time with no automatic cleanup. Mitigation:
move old plans to `plans/archive/` periodically; git history preserves everything.

## 4. `~/.claude/settings.json` accumulated grants wiped on every install

**The decision**: `install.sh` regenerates `~/.claude/settings.json` from the repo's
source files. One-shot grants approved interactively since the last install are lost from
the active settings (preserved in the backup file).

**The alternative considered**: merge the existing local allow list into the new one.

**Why we chose wipe-and-regenerate**:

1. **Accumulated grants are almost all junk.** One-shot command variants with specific
   project paths and build flags you'll never see again. Merging them forward accumulates noise.
2. **Forces a promotion discipline.** When you miss a specific pattern, you promote it
   deliberately (add to `settings.base.json`, commit, push). That gives cross-machine
   sync for free and documents which permissions you actually depend on.
3. **The backup file is a safety net.** Every install backs up the old settings.json. Grep
   the backup for a pattern and promote it. No data is ever lost.
4. **File always matches the repo.** One source of truth, deterministic output. No drift,
   no "which is authoritative," no cross-machine inconsistency.

**What we gave up**: the first day after reinstall, you may get prompted for patterns
that used to be pre-approved. Cost: a few seconds of clicks. Worth the structural clarity.

## 5. Copilot reads a generated instructions file (not CLAUDE.md directly)

**The decision**: `install.sh` generates `copilot-prompts/claude-global.instructions.md`
by prepending `applyTo: "**"` frontmatter to `CLAUDE.md`, and symlinks it into VS Code's
`User/prompts/` directory. Copilot finds it automatically.

**Alternatives considered**:

A. **Symlink `CLAUDE.md` directly into `User/prompts/`** — Copilot's instructions file
   format requires the `applyTo` frontmatter. Adding it to `CLAUDE.md` would cause Claude
   Code to choke on it. Same file can't serve both tools.

B. **Paste the path into VS Code `settings.json`** via `codeGeneration.instructions`. This
   was the original approach. It works but: (1) that setting is deprecated in favor of the
   instructions file mechanism, and (2) VS Code Settings Sync pushes the Mac absolute path
   to Windows where it doesn't exist. We hit the Settings Sync problem during build and
   switched approaches.

C. **Keep two copies in sync manually** — guaranteed to drift.

**Why we chose generate-and-symlink**:

1. Single source of truth — `CLAUDE.md` is authoritative, the instructions file is derived.
2. Both tools get consistent content — same bytes, different wrappers.
3. No Settings Sync problems — nothing about the wiring lives in VS Code's synced settings.
4. No drift possible — regenerated on every install.
5. Respects the deprecation — uses the mechanism VS Code wants.

**What we gave up**: editing `CLAUDE.md` requires re-running `install.sh` to regenerate.
Minor friction, documented in the edit-sync matrix ([07-operator-guide.md](07-operator-guide.md)).

## 6. `MSYS=winsymlinks:nativestrict` forced in install.sh

**The decision**: `install.sh` and `preflight.sh` both export `MSYS=winsymlinks:nativestrict`
at the top on Windows (MINGW/MSYS/Cygwin detected).

**The alternative considered**: tell the user to set it in `~/.bashrc` manually.

**Why we chose scripting it**:

1. **It's load-bearing and non-obvious.** Without it, Git Bash creates fake MSYS symlinks
   that silently fail `[ -L ]`. Install would "succeed" but everything would be broken.
2. **Documenting it isn't enough.** Even with documentation, this was the failure mode
   encountered during initial Windows setup. A manual step is one more thing to forget.
3. **Forcing it at script top means the script always runs with real symlinks.** No
   ambiguity, no environment-dependent behavior.
4. **It's a no-op on Mac/Linux.** The `case "$(uname -s)"` only triggers on Windows.

**What we gave up**: nothing meaningful. Other Git Bash sessions don't get the export
unless the user adds it to `~/.bashrc` themselves.

## 7. Symlinks, not copies

**The decision**: `install.sh` symlinks most files from the repo into `~/.claude/`, rather
than copying them.

**The alternative considered**: copy files. Simpler on Windows (symlinks have historically
been fraught). More predictable for users unfamiliar with symlinks.

**Why we chose symlinks**:

1. **Edits are immediately live.** Edit `commands/ticket-new.md` and the change is visible
   to Claude Code instantly — no reinstall, no sync step.
2. **No risk of forgetting to sync.** With copies you'd have to reinstall after every edit.
3. **Git sees edits naturally.** `~/.claude/commands/ticket-new.md` IS `commands/ticket-new.md`
   via symlink — `git diff` works directly.
4. **Windows finally supports them properly.** With Developer Mode + `nativestrict`, the
   historical Windows symlink pain is gone.

**What we gave up**: install depends on symlink capability, requiring Developer Mode on
Windows. Documented as a prerequisite.

## 8. `preflight.sh` is a separate script (not folded into `install.sh`)

**The decision**: preflight is its own read-only script, strongly recommended before install.

**The alternative considered**: have `install.sh` run preflight checks first and abort on failures.

**Why we chose separation**:

1. **Read-only vs. mutating is a meaningful distinction.** `preflight.sh` promises not to
   touch anything; `install.sh` promises to make changes. Separation makes the promise clearer.
2. **Preflight on a new machine is reassuring.** You can run it, read the output, decide
   if you trust the install, then proceed. Folding removes the "stop and think" moment.
3. **Preflight can be run without installing.** Useful for debugging: "what's wrong with
   my environment?" doesn't require a commit.
4. **The failure report is the point.** Preflight's output is the deliverable (a checklist
   of working vs. not). Folding into install would hide that behind an "aborted" message.

**What we gave up**: nothing — `bash preflight.sh && bash install.sh` is still a one-liner.

## 9. Tickets live in each project, not in this repo

**The decision**: `claude-config` contains the commands and templates for the ticket system,
but ticket state is per-project: configured via `.claude/ticket-config.md` and
`.claude/plane-config.md`. Each project has its own Plane project (or legacy `tickets/`
directory).

**The alternative considered**: centralize all tickets in the dotfiles repo, keyed by project name.

**Why we chose per-project**:

1. **Tickets belong with the code they describe.** When you `git blame` a line and find it
   was added for SMOKE-12, you can open that ticket in the project's backend. Going to a
   separate dotfiles repo for context is worse.
2. **Project repos are the right sharing unit.** Collaborators see the tickets automatically
   — Plane: via the shared workspace; markdown: via the project repo. If tickets lived in
   personal dotfiles, collaborators would need access to your dotfiles.
3. **Brief / delegation artifacts belong with tickets.** A brief is scoped to a specific
   ticket; the ticket is scoped to the project.

**What changed with Plan 2 (Plane backend)**:

Since Plan 2, the default backend is Plane. The decision to keep tickets per-project still
holds — each repo has its own Plane project — but the "tickets in git history" traceability
rationale no longer applies for Plane-backed projects. We traded `git blame → TKT-N.md`
traceability for a shared cross-machine source of truth that handles concurrent agent loops
correctly. The markdown backend remains supported for projects that haven't migrated.

**What we gave up**: no cross-project ticket view for markdown projects. For Plane projects,
the Plane workspace dashboard is the cross-project view.

## 10. `effortLevel: "max"` in base settings

**The decision**: `settings.base.json` sets `effortLevel: "max"` universally.

**Why**:

1. Explicitly used in daily work — this was in the existing Windows config, indicating preference.
2. The alternative (default or lower) would be a silent regression in model quality.
3. If you ever want per-machine variation, add an override in `settings.{mac,windows}.json`.

**Watch-out**: `effortLevel: "max"` can be slower and more expensive per token. If you're
budget-conscious on a specific machine, this is the knob to turn down. The decision is
global but easy to override per-platform.

## The meta-decision: document the reasoning

The one overarching "why" that applies to this whole doc: **future-you won't remember why
you made these calls**. Without this document, when you come back in a year and think "why
did we do cross-model delegation via files instead of just calling Gemini from Claude Code?",
you'll rediscover the reasoning the slow way.

When you change any of these decisions, update this document. Add a new section explaining
why the new decision is better and what changed. The value is maintained reasoning, not a
snapshot.
