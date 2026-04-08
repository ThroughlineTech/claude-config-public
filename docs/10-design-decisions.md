# Design Decisions

Non-obvious design choices in this repo, with the reasoning behind each. Read this when you're tempted to change something and wondering "why was it done this way?" — there may be a reason you're about to rediscover the hard way.

## 1. Cross-model delegation via briefs (not direct API calls)

**The decision**: `/ticket-delegate` writes a self-contained markdown brief file. You manually switch to Copilot Chat, pick a model, and run `/run-brief {path}`. The executing agent writes results back into the ticket file. You come back to Claude Code and run `/ticket-collect`.

**The alternative considered**: have Claude Code invoke Gemini directly via some API hook so the delegation is seamless — no manual tool switching.

**Why we chose briefs**:

1. **Claude Code can't actually invoke Copilot Chat.** There's no API bridge. Even if we wanted the "seamless" approach, it doesn't exist with current tools.
2. **Filesystem-as-bridge is model-agnostic.** Today it's Gemini. Tomorrow it's GPT-5 or Claude Opus 5 or something we haven't heard of yet. The brief format doesn't care — any model that can read markdown and execute tool calls can execute a brief. No API adapter per model, no version lock-in.
3. **Human-in-the-loop is a feature, not a bug.** The manual tool-switch is friction, but the friction is what keeps you steering per-ticket decisions ("is Gemini really better for this, or should Claude Code just do it?"). Automating the handoff would remove that judgment call and make it easy to over-delegate.
4. **Briefs are inspectable and auditable.** You can read a brief before executing it, after executing it, and six months later. The ticket file accumulates the audit trail: which agent did what when. An API-based delegation would leave much less of a trace.
5. **Briefs can be executed by things other than Copilot.** You could hand a brief to another Claude Code session, to Aider, to Cursor, to a junior developer who reads the brief and types it out by hand. The format is universal.

**What we gave up**: ~5 minutes of tool-switching overhead per delegation. Worth it for every point above.

## 2. Platform-split settings with jq merge (not one settings.json)

**The decision**: `settings.base.json` for universal settings, `settings.mac.json` and `settings.windows.json` for platform-specific additions, merged at install time via jq.

**The alternative considered**: one `settings.json` with everything in it, or one per machine.

**Why we chose the split**:

1. **No absolute paths in synced files.** A single `settings.json` with Mac-specific `Bash(xcodebuild:*)` and Windows-specific `Bash(powershell:*)` is confusing on both machines; both see entries that don't apply to them. The split keeps each file focused.
2. **Clean allow list.** The base file is about 40 entries of universal tools (`git`, `npm`, `grep`, `curl`, etc.). The platform files are about 10-15 entries each of OS-specific tools. Together they're comprehensible; merged manually they'd be 60+ entries in one file with no structure.
3. **Easier to promote grants.** When you hit a new pattern on Mac that's Mac-specific, it goes into `settings.mac.json`. When it's universal, it goes into `settings.base.json`. The placement is obvious from the nature of the command.
4. **jq merge is idempotent and debuggable.** Running the merge twice produces the same file. You can see the merge command in `install.sh` and replicate it manually to debug.

**What we gave up**: a little install complexity (the jq merge expression is not trivial). Worth it for structural cleanliness.

## 3. Plans live in the repo (not local-only)

**The decision**: the `plans/` directory is synced via git like everything else in the repo. `claude-handoff` pushes the most recent plan under a pointer name (`_next.md`) so the other machine knows which plan to execute.

**The alternative considered**: keep plans local to each machine and provide no sync mechanism. Or sync plans via a shared filesystem (Dropbox, iCloud).

**Why we chose git-synced:**

1. **Git handles conflicts explicitly.** If both machines write plans simultaneously (rare but possible), git surfaces the conflict and you resolve it. Dropbox would silently overwrite.
2. **Plan history becomes durable and searchable.** You can grep old plans, see when a plan evolved (`git blame`), reference prior design work. Plans become a knowledge artifact, not ephemeral local state.
3. **Same sync mechanism as everything else.** `git pull` gets you commands, templates, AND plans. No second sync tool to manage.
4. **Plans are an obvious fit for "cross-machine handoff"** — you specifically mentioned "build a plan on my laptop, execute on the always-on desktop" as a use case. Syncing plans is the enabling infrastructure for that.

**What we gave up**: plans accumulate in the repo over time. There's no automatic cleanup. Mitigation: you can periodically move old plans to `plans/archive/` or delete them via git, and the git history preserves everything regardless.

## 4. `~/.claude/settings.json` accumulated grants are wiped on every install

**The decision**: `install.sh` regenerates `~/.claude/settings.json` from the repo's source files. Any one-shot grants you approved interactively since the last install are lost from the active settings (but preserved in the backup file).

**The alternative considered**: merge the existing local `settings.json`'s allow list into the new one, preserving accumulated grants across installs.

**Why we chose wipe-and-regenerate:**

1. **Accumulated grants are almost all junk.** Your Mac had 200+ entries, most of which were one-shot command variants (`xcodebuild -project X -scheme Y -destination Z -configuration Debug build`) that you'll never see again. Merging them all forward just accumulates noise.
2. **Forcing a clean regeneration creates a promotion discipline.** When you notice you miss a specific pattern, you promote it deliberately (add to `settings.base.json`, commit, push). That gives you cross-machine sync for free and documents which permissions you actually depend on.
3. **The backup file is a safety net.** Every install backs up the old settings.json. If you notice you're missing something, you can grep the backup for the pattern and promote it. No data is ever actually lost.
4. **Wipe-and-regenerate means the file matches the repo.** There's one source of truth (the JSON files in the repo), and `~/.claude/settings.json` is always a deterministic function of them. No drift, no "which is authoritative," no subtle cross-machine inconsistency.

**What we gave up**: the first day after reinstall, you may get prompted for a few patterns that used to be pre-approved. Cost: a few seconds of clicks. Benefit: structural simplicity and cross-machine consistency. Worth it.

## 5. Copilot reads a generated instructions file (not CLAUDE.md directly, not settings.json)

**The decision**: `install.sh` generates `copilot-prompts/claude-global.instructions.md` by prepending `---\napplyTo: "**"\n---\n\n` to `CLAUDE.md`'s content, and symlinks the result into VS Code's `User/prompts/` directory. Copilot finds it automatically.

**The alternatives considered**:

A. **Symlink `CLAUDE.md` directly into `User/prompts/`** — simpler, but Copilot's instructions file format requires the `applyTo` frontmatter, and `CLAUDE.md` doesn't have it. Claude Code would choke on the frontmatter if it were added, so the same file can't serve both tools.

B. **Paste the path into VS Code `settings.json`** via the `github.copilot.chat.codeGeneration.instructions` setting. This was the original approach. It works but has two fatal problems: (1) the setting is deprecated in favor of the instructions file mechanism, and (2) if you have VS Code Settings Sync enabled, the absolute Mac path gets pushed to Windows where it doesn't exist. We hit the Settings Sync problem during build and switched approaches.

C. **Keep two copies of the content in sync manually** — you edit `CLAUDE.md` and remember to also update `claude-global.instructions.md`. Terrible; guaranteed to drift.

**Why we chose generate-and-symlink:**

1. **Single source of truth** — `CLAUDE.md` is authoritative, the instructions file is derived.
2. **Both tools get consistent content** — same bytes, different wrappers.
3. **No Settings Sync problems** — nothing about the wiring lives in VS Code's synced settings. Each machine's install creates the file locally.
4. **No drift possible** — the generated file is regenerated on every install, so it's always current.
5. **Respects the deprecation warning** — uses the new mechanism VS Code wants.

**What we gave up**: editing `CLAUDE.md` requires re-running `install.sh` to regenerate the instructions file. Minor friction, documented in [07-editing-and-syncing.md](07-editing-and-syncing.md).

## 6. `MSYS=winsymlinks:nativestrict` forced in install.sh (not left to the user)

**The decision**: `install.sh` and `preflight.sh` both export `MSYS=winsymlinks:nativestrict` at the top of the script on Windows (MINGW/MSYS/Cygwin detected).

**The alternative considered**: tell the user to set it in their `~/.bashrc` manually.

**Why we chose scripting it:**

1. **It's load-bearing and non-obvious.** Without it, Git Bash creates fake MSYS symlinks that silently fail `[ -L ]`. The install script would "succeed" but everything would actually be broken. The user wouldn't realize until they edited a file and it didn't propagate.
2. **Documenting it isn't enough.** You told me "developer mode is on" and we still got the fake-symlink failure because MSYS mode wasn't set. A manual setup step is one more thing to forget or get wrong.
3. **Forcing it at the top of the script means the script always runs with real symlinks.** No ambiguity, no environment-dependent behavior.
4. **It's a no-op on Mac/Linux.** The `case "$(uname -s)"` only triggers on Windows; other platforms don't care.

**What we gave up**: nothing meaningful. The user's other Git Bash sessions don't get the export unless they add it to their `.bashrc` themselves — but that only matters if they're manually creating symlinks outside of `install.sh`, which is rare.

## 7. Symlinks, not copies

**The decision**: `install.sh` symlinks most files from the repo into `~/.claude/`, rather than copying them.

**The alternative considered**: copy files. Simpler on Windows (symlinks have historically been fraught). More predictable for users who don't know what symlinks are.

**Why we chose symlinks:**

1. **Edits are immediately live.** Edit `commands/ticket-new.md` in the repo and the change is visible to Claude Code instantly — no re-install, no "sync" step.
2. **No risk of forgetting to sync.** With copies, you'd have to re-install after every edit to propagate the change. Easy to forget, confusing when you forget.
3. **Git sees edits naturally.** Because `~/.claude/commands/ticket-new.md` IS `~/src/claude-config/commands/ticket-new.md` (via symlink), you can `git diff` the file by path and see your pending edits immediately.
4. **Windows finally supports them properly.** With Developer Mode and `MSYS=winsymlinks:nativestrict`, Windows real symlinks work in Git Bash. The historical pain is gone.

**What we gave up**: the install process depends on symlink capability, which requires Developer Mode on Windows. Documented as a prerequisite.

## 8. `preflight.sh` is a separate script (not folded into `install.sh`)

**The decision**: preflight is its own script, read-only, that must be run before install (or at least is strongly recommended).

**The alternative considered**: make `install.sh` run preflight checks first and abort if any fail.

**Why we chose the separation:**

1. **Read-only vs. mutating is a meaningful distinction.** `preflight.sh` promises to not touch anything; `install.sh` promises to make changes. Keeping them separate makes the promise clearer and the review safer.
2. **Preflight on a new machine is reassuring.** You can run it, read the output, decide if you trust the install, then run install. Folding them into one script removes the "stop and think" moment.
3. **Preflight can be run without installing.** Useful for debugging: "what's wrong with my environment?" doesn't require a commit to find out.
4. **The failure report is the point.** Preflight's output is the deliverable (a checklist of what's working and what isn't). Folding into install would hide that behind an "aborted" message.

**What we gave up**: nothing — you can still run them together (`bash preflight.sh && bash install.sh` is a one-liner). The separation doesn't prevent combining them; it just makes preflight a first-class thing with a name.

## 9. Tickets live in each project, not in this repo

**The decision**: `claude-config` contains the commands and templates for the ticket system, but actual ticket files live in each project's own `tickets/` directory (configured via `.claude/ticket-config.md` in the project).

**The alternative considered**: centralize all tickets in the dotfiles repo, keyed by project name.

**Why we chose per-project:**

1. **Tickets belong with the code they describe.** When you `git blame` a line and find it was added for TKT-123, you can open TKT-123 in the same repo. Going to a separate dotfiles repo to find ticket context is worse.
2. **Project repos are the right sharing unit.** If you collaborate on a project, collaborators see the tickets automatically via the project repo. If tickets lived in your personal dotfiles, collaborators would need access to your dotfiles to see them.
3. **Tickets in each project's git history are permanent.** Tied to the commits that implemented them. If you delete the dotfiles repo, you don't lose project-specific work.
4. **Brief files belong with tickets.** Same reason — a brief is about a specific ticket, and the ticket is in the project, so the brief is in the project.

**What we gave up**: no cross-project ticket view. You can't easily answer "show me every open ticket across all my projects." Solution when you need it: a script that greps `~/src/*/tickets/TKT-*.md` and reports by status. Easy to add later; low priority until you have 5+ active projects using the ticket system.

## 10. `effortLevel: "max"` in base settings

**The decision**: `settings.base.json` sets `effortLevel: "max"` universally.

**Why**:

1. You explicitly use max effort in daily work — this was in your existing Windows config, indicating preference.
2. The alternative (default or lower) would cost you model quality and be a silent regression.
3. If you ever want per-machine variation, add an override in `settings.{mac,windows}.json` (or delete the key from base and put it in each platform file).

**Watch-out**: `effortLevel: "max"` can be slower and more expensive per token. If you're budget-conscious on a specific machine, this is the knob to turn down. The decision is global but easy to override per-platform.

## The meta-decision: document the reasoning

The one overarching "why" that applies to this whole doc: **future-you won't remember why you made these calls**. Without this document, when you come back in a year and think "why did we do cross-model delegation via files instead of just calling Gemini from Claude Code?", you'll rediscover the reasoning the slow way (by trying the "obvious" alternative and hitting the exact problems this doc explains).

When you change any of these decisions, update this document. Add a new section explaining why the new decision is better and what changed. The value of the doc is maintained reasoning, not a snapshot.
