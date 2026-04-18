# Maintenance Cadence

Recommended ops cadence to keep `claude-config` healthy over time. The repo mostly takes care of itself, but there are a few things that will rot if you never revisit them.

## Daily (automatic, no effort required)

Nothing. The system is designed so daily use costs you nothing in maintenance. You just run slash commands, edit code, use Copilot, and the infrastructure does its job.

The only thing that happens in the background is that your local `~/.claude/settings.json` may accumulate new one-shot permission grants as you approve them interactively. That's fine — they're not lost, they're just local until you promote them.

## Weekly (2 minutes, optional)

**Pull the repo on every machine you've used this week.**

```bash
cd ~/src/claude-config && git pull
# If the pull touched CLAUDE.md, plan-mode.md, brainstorm-mode.md, or settings.*.json, re-install:
bash install.sh
```

If you've folded `git -C ~/src/claude-config pull` into your `sync-repos` script, this is automatic — just keep using `sync-repos`. Skip this step if you've only used one machine and the other is asleep.

**Skim the week's plans.**

```bash
ls -t ~/.claude/plans/*.md | head -5
```

Five most recent plans. Did any of them turn into anything you should clean up (move to archive, delete the `_next.md` pointer)? Most weeks: no action needed.

## Monthly (15-30 minutes, mildly important)

**1. Mine accumulated permission grants.**

Pick the machine you used most this month. Look at what's accumulated in `~/.claude/settings.json`:

```bash
# Count total allow entries
jq '.permissions.allow | length' ~/.claude/settings.json
# Show the ones added since last install (by diffing with the repo)
diff <(jq -r '.permissions.allow[]' ~/.claude/settings.json | sort) \
     <(jq -r '(.permissions.allow + .permissions.allow) | .[]' \
         ~/src/claude-config/settings.base.json ~/src/claude-config/settings.mac.json 2>/dev/null | sort) \
     | grep '^<'
```

Anything you see that's a broad-enough pattern to promote? Look for:
- Patterns like `Bash(tool-name:*)` that cover a whole tool (promote these aggressively)
- Recurring specific commands you use often (maybe promote with a narrower pattern if `*` is too broad)

Ignore:
- One-shot command variants with specific file paths, IDs, or timestamps
- Anything with a credential, token, or URL — those shouldn't be in `permissions.allow` at all

Promote by editing the relevant settings file in the repo (`settings.base.json` for universal, `settings.mac.json`/`settings.windows.json` for platform-specific), committing, pushing, and re-running `install.sh` on each machine.

**2. Delete old backups.**

`install.sh` creates backups every time it replaces something. They pile up.

```bash
ls -la ~/.claude/*.backup.* ~/.claude/*/*.backup.* 2>/dev/null
```

Delete what you don't need:

```bash
# Safe to delete after a week
rm -rf ~/.claude/commands.backup.*
rm -rf ~/.claude/plans.backup.*
rm -rf ~/.claude/brief-templates.backup.*
rm ~/.claude/CLAUDE.md.backup.*
rm ~/.claude/plan-mode.md.backup.*
rm ~/.claude/brainstorm-mode.md.backup.*

# Keep settings.json.backup.* LONGER — it's the only place accumulated grants live
# until you promote them. Delete after a month, or after you've mined it.
```

**3. Check that both machines are in sync.**

```bash
# On machine A
cd ~/src/claude-config && git log --oneline -5

# On machine B
cd ~/src/claude-config && git log --oneline -5
```

Same top commit = in sync. Different top commits = someone has un-pulled changes. Pull and sync.

**4. Glance at the plans directory.**

```bash
ls ~/src/claude-config/plans/ | wc -l
```

If it's in the hundreds, consider archiving old ones (move to `plans/archive/`, git history preserves everything anyway).

## Per-machine events (do once, when triggered)

### When you get a new machine

Follow [06-adding-a-new-machine.md](06-adding-a-new-machine.md). 5 minutes. Nothing else to do.

### When you decommission a machine

1. Make sure any in-progress plans on that machine are pushed: `cd ~/src/claude-config && git status && git push`
2. Nothing else. The repo is the source of truth; once you've confirmed it's pushed, the local machine can be wiped without losing anything.

### When you rotate your Prowl API key

1. Generate a new key at prowlapp.com
2. Edit `CLAUDE.md` and `copilot-prompts/run-brief.prompt.md` — replace the old key with the new one everywhere
3. Commit: `git commit -am "rotate: new prowl API key"`
4. Push
5. On every machine: `git pull && bash install.sh`
6. Test: "send me a test prowl" in both Claude Code and Copilot Chat on each machine
7. Invalidate the old key at prowlapp.com once you've confirmed the new one works

## Per-change events (whenever you edit something)

### When you edit `CLAUDE.md`, `plan-mode.md`, or `brainstorm-mode.md`

On the machine where you edited: re-run `install.sh` to regenerate the matching Copilot instructions file. Commit. Push. On other machines: pull, re-run `install.sh`.

### When you edit a settings file

Same as CLAUDE.md — re-run `install.sh` to regenerate `~/.claude/settings.json`.

### When you edit a command or brief template

Commit. Push. On other machines: pull. No re-install needed (symlinked files are live).

If the edited file is a `commands/ticket-*.md` (or any non-alias command), also sync its Copilot counterpart so Copilot Chat stays behaviorally current:

```
# In Claude Code or Copilot Chat:
/sync-claude-command commands/<name>.md

# Or to refresh everything at once:
/sync-claude-command --all
```

Alias files (`tn.md`, `tch.md`, etc.) do not need syncing — their Copilot counterparts are thin delegates that never change when the canonical command changes.

The sync generates or updates `copilot-prompts/<name>.prompt.md` and prints a Preserved / Adapted / Unsupported report. Commit the updated prompt file in the same commit as the command change.

### When you add a new plan via plan mode

Nothing automatically — plans accumulate in `plans/`. If you want to hand it off: `claude-handoff`. Otherwise it'll sit in the repo until you push it naturally (next time you commit anything else in the repo).

## Semi-annual (30-60 minutes, when you feel like it)

**1. Review the docs.**

Read through `docs/` and the README. Anything wrong, outdated, or unclear? Fix it. Docs drift is silent and expensive over long time horizons.

Specifically look for:
- Sections that describe a command or behavior that's changed
- Examples that use an old file path or command format
- "TODO: future improvement" notes that can now be checked off or removed

**2. Audit the command files.**

```bash
ls ~/src/claude-config/commands/
```

For each command: is the behavior still what you want? Are there things you find yourself manually working around? Is there a command you added "for future use" that you've never actually run?

Don't over-edit. If a command is working fine, leave it. But six months of real use will reveal which commands are essential and which are just cruft.

**3. Audit the brief templates.**

Same thing for `brief-templates/`. Which templates have you actually used? Which ones are hypothetical? The three `verify-*` templates especially — if you've never done a peer-review, consider whether they're worth keeping as-is or simplifying.

**4. Look at your deny list.**

```bash
jq '.permissions.deny' ~/.claude/settings.json
```

Should contain at least `rm -rf /`, `rm -rf /*`, `chmod:*`, `wget:*`, `sudo:*`. Any new "never let an agent do this" rules you've learned in six months of use? Add them to `settings.base.json`.

**5. Check the CHANGELOG.**

Has it been updated since version 0.1.0? If you've made meaningful changes, add entries. If not, no action.

## Annual (or "when something big changes"): structural review

Once a year (or when you significantly change how you work with agents), step back and ask:

- **Is the layer model (Layer 1: repo, Layer 2: ~/.claude/, Layer 3: tools) still the right abstraction?** If yes, great. If no, what would you change?
- **Are you using the ticket workflow? The delegation system?** If not, either revive them or retire them. Dead code is worse than no code.
- **Is `CLAUDE.md` still the right shape?** It should be short (under 100 lines of actual content). If it's grown to 500 lines, some of that should probably split into per-project CLAUDE.md files.
- **Have the tools changed in ways that make the workflow obsolete?** (e.g. if Copilot adds native Claude Code interop, the brief-based delegation might be replaceable with direct calls.) Rewrite the parts that need rewriting.
- **Are there conventions you've developed in daily use that should be promoted from "something you do" to "something documented"?**

This is a 1-hour meditation, not a major refactor. The point is to keep the system aligned with how you actually work, rather than with how you worked when you first built it.

## Red flags that need immediate attention

**Settings merge producing empty or invalid JSON.** If `jq .effortLevel ~/.claude/settings.json` ever fails or returns null, something broke in the merge. Re-run `bash install.sh` with `-x` to see where it went wrong.

**Broken symlinks in `~/.claude/`.** If `ls -la ~/.claude/CLAUDE.md` shows a symlink but `cat` fails with "No such file or directory," the repo has moved or been deleted. Re-clone to the expected path and re-run install.

**Growing accumulated grants (100+ in a week).** If your local `permissions.allow` is ballooning faster than normal, Claude Code is prompting for lots of things it shouldn't. Look at what's being added — you're probably missing a broad pattern that should be in the base.

**`claude-handoff` consistently reporting "no plans found".** You're probably running it from the wrong directory, or your plan mode isn't writing to `~/.claude/plans/`. Check: `ls -la ~/.claude/plans/` should be a symlink into the repo; plans written in plan mode should land there.

**Copilot suddenly not loading instructions.** Check that the instructions file still exists at `~/Library/Application Support/Code/User/prompts/claude-global.instructions.md` (Mac) and is a valid symlink. VS Code updates occasionally change the prompts directory; re-run `install.sh` to recreate the symlink if needed.

## The minimum viable maintenance

If you only do ONE thing regularly: **re-run `bash install.sh` on each machine after any git pull that touched `CLAUDE.md`, `plan-mode.md`, `brainstorm-mode.md`, or settings files.** That's the only maintenance task that is load-bearing. Everything else on this page is polish.

If you forget everything on this page for six months, the system will still work. It just won't be optimally tidy, and your accumulated grants will be bloated. Pick it up when you next think to.
