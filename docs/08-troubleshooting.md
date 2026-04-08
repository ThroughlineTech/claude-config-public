# Troubleshooting

Real failure modes we hit while building this, with fixes. Organized by symptom.

## Install failures

### `jq: command not found` during settings merge

**Symptom**: `install.sh` prints `⚠ jq not installed; skipping settings merge.`

**Fix**: install jq, close and reopen your shell, re-run `install.sh`.

| Platform | Command |
|---|---|
| macOS | `brew install jq` |
| Linux (Debian/Ubuntu) | `sudo apt install jq` |
| Linux (Fedora) | `sudo dnf install jq` |
| Windows (winget) | `winget install jqlang.jq` |
| Windows (scoop) | `scoop install jq` |

After installing on Windows, the new `jq` may not be on PATH in your current Git Bash session. Close all Git Bash windows and reopen.

### `ln -s` fails with "No such file or directory" for the target

**Symptom**: a one-off `ln -s /tmp/foo /tmp/test-link` fails with `No such file or directory`, even though `/tmp` exists.

**Cause**: On Windows, `ln -s` requires the target file to already exist (Windows symlinks have different types for files vs directories and Git Bash needs to inspect the target to pick the right type). Linux/Mac let you create dangling symlinks; Windows doesn't.

**Fix**: this is only a problem for manual symlink tests. `install.sh` and `preflight.sh` always symlink to files that exist (the repo contents), so they don't hit this. If you want to test symlinks manually on Windows:

```bash
echo test > /tmp/foo && ln -s /tmp/foo /tmp/test-link && readlink /tmp/test-link && rm /tmp/test-link /tmp/foo
```

Should print `/tmp/foo`.

### Preflight `[3]` reports "ln -s ran but the result is not a symlink" on Windows

**Symptom**: on Git Bash for Windows, preflight's symlink test fails even though `ln -s` ran without error.

**Cause**: By default, Git Bash creates "fake" MSYS symlinks — regular files with special content that MSYS tools interpret as symlinks but Windows-native apps (including Claude Code, VS Code, and the bash `[ -L ]` test) see as regular files. Useless for our purpose.

**Fix**: Force MSYS to create real Windows symlinks:

```bash
export MSYS=winsymlinks:nativestrict
bash preflight.sh
```

Preflight should now report `[3] ✓ ln -s creates real symlinks`. Persist the export by adding it to your `~/.bashrc`:

```bash
echo 'export MSYS=winsymlinks:nativestrict' >> ~/.bashrc
```

**Note**: `install.sh` (current version) does this export automatically at the top of the script. If you're on an older version of install.sh and hitting this, pull the latest from the repo.

**Also requires**: Windows Developer Mode enabled (Settings → System → For developers → Developer Mode: On). This lets non-admin users create real symbolic links. If Developer Mode is off, even `winsymlinks:nativestrict` can't create real symlinks — the OS blocks it.

### "Permission denied" when creating symlinks

**Symptom**: `install.sh` fails with "Operation not permitted" or "Permission denied" on symlink creation.

**Cause**:
- Mac/Linux: you probably don't own `~/.claude/` (rare; would happen if you created it as another user).
- Windows: Developer Mode is off AND you're not running Git Bash as administrator.

**Fix**:
- Mac/Linux: `sudo chown -R $USER ~/.claude` and re-run install.
- Windows: turn on Developer Mode (permanent fix), OR right-click Git Bash → "Run as administrator" just for the one `bash install.sh` invocation. The symlinks persist after you close the elevated shell.

### Smoke tests fail at the end of install.sh

**Symptom**: `install.sh` runs through most of its steps but then prints `✗ {something} not symlinked`.

**Fix**: read the exact error. Common causes:

- If multiple symlinks are missing: something interrupted the script (Ctrl+C, terminal closed). Re-run.
- If one specific symlink is missing: that target directory/file might not exist in the repo. Check `ls ~/src/claude-config/{path}`.
- If `settings.json effortLevel != max`: the jq merge didn't run, or ran on the wrong files. Check that `settings.base.json` has `"effortLevel": "max"` at the top level. Run the jq command manually to see where it went wrong.

### `install.sh` says it's done but symlinks don't resolve

**Symptom**: `install.sh` reports success but `cat ~/.claude/CLAUDE.md` shows "No such file or directory" or wrong content.

**Cause**: The symlinks were created pointing at a path that doesn't exist, OR the repo was moved after install.

**Fix**: re-run `install.sh`. The `DOTFILES="$(cd "$(dirname "$0")" && pwd)"` line at the top captures the absolute path of the repo at install time, so symlinks point at that absolute path. If you move the repo, the symlinks break — re-run install from the new location.

## Claude Code issues

### Claude Code says it doesn't know about Prowl when I say "prowl me"

**Symptom**: you tell Claude Code "send me a prowl" and it asks what that means.

**Diagnosis**:
```bash
ls -la ~/.claude/CLAUDE.md
cat ~/.claude/CLAUDE.md | head -20
```

**Possible causes**:

1. `~/.claude/CLAUDE.md` is not a symlink, or symlink is broken → re-run `install.sh`.
2. `~/.claude/CLAUDE.md` symlink points at an empty or wrong file → verify the target with `readlink ~/.claude/CLAUDE.md`, check the target exists and has content.
3. You're in a project with a project-level `CLAUDE.md` that doesn't include Prowl instructions → Claude Code uses the innermost CLAUDE.md; the global one is inherited but project rules take precedence on conflicts. Check `cat $(pwd)/CLAUDE.md` if it exists.
4. Your Claude Code session was started before `install.sh` created the symlink → start a new Claude Code session.

### Claude Code asks for permission for something I thought I allowed globally

**Symptom**: You approved `Bash(git push)` in the past but Claude Code is prompting for it again.

**Cause**: `install.sh` regenerated `~/.claude/settings.json` and wiped the accumulated grant.

**Fix**: the broader pattern you want is probably already in the base — `Bash(git:*)` should cover all git commands. If it's not:

1. Check your current allows: `jq '.permissions.allow' ~/.claude/settings.json | grep -i git`
2. If the broad pattern isn't there, add it to `settings.base.json` in the repo.
3. Commit, push, re-run `install.sh`.

If the pattern is there but still being prompted, Claude Code may be checking something more specific than the pattern matches. Open an issue with specifics.

### `/ticket-new` says "ticket config not found" in a project

**Symptom**: running a ticket command in a project prints a message like "run /ticket-install first".

**Cause**: the project hasn't been bootstrapped with `/ticket-install` yet.

**Fix**: in the same Claude Code session, run `/ticket-install`, answer the prompts, then retry.

## Copilot issues

### "send me a test prowl" in Copilot doesn't work

**Symptom**: you ask Copilot for a test prowl and it either:
- Asks what that means (instructions file not loaded)
- Shows the curl command but doesn't execute it (Ask mode, not Agent mode)
- Executes something wrong (instructions file is stale or corrupted)

**Diagnosis sequence**:

1. **Verify the instructions file is in the right place:**
   ```bash
   # Mac
   ls -la "$HOME/Library/Application Support/Code/User/prompts/claude-global.instructions.md"
   # Windows Git Bash
   ls -la "$APPDATA/Code/User/prompts/claude-global.instructions.md"
   ```
   Should be a symlink pointing into the repo.

2. **Verify it has the right frontmatter:**
   ```bash
   head -5 ~/src/claude-config/copilot-prompts/claude-global.instructions.md
   ```
   Should start with:
   ```
   ---
   applyTo: "**"
   ---
   ```

3. **Verify Copilot Chat is in Agent mode, not Ask mode.** There's a toggle in the chat input area in VS Code. Ask mode only talks; Agent mode executes tools.

4. **Start a NEW Copilot Chat conversation** (click "+" or "New Chat"). Existing conversations may not pick up the instructions.

5. **Switch the model and try again** — some models are worse at following "execute this curl" instructions than others.

6. **Check that CLAUDE.md still has the Prowl section with the right key:**
   ```bash
   grep -A 5 "Prowl" ~/src/claude-config/CLAUDE.md
   ```

### VS Code shows "Use instructions files instead" warning on settings.json

**Symptom**: You have `"github.copilot.chat.codeGeneration.instructions"` in your VS Code `settings.json` and VS Code squiggles it with a deprecation warning.

**Fix**: Remove the line from `settings.json`. The instructions file at `User/prompts/claude-global.instructions.md` is the new mechanism and it's what we use. The deprecated settings.json key is redundant.

### VS Code Settings Sync pushed a Mac absolute path to Windows

**Symptom**: On Windows, VS Code complains about a path that starts with `/Users/...` (a Mac-style absolute path that doesn't exist on Windows)

**Cause**: Earlier in this repo's history, we tried using `"github.copilot.chat.codeGeneration.instructions"` with an absolute file path. VS Code Settings Sync then pushed that Mac-absolute path to Windows, where it's nonsensical.

**Fix**: Remove the key from VS Code settings.json on both machines. The instructions-file mechanism doesn't have this problem because the file path is known to VS Code internally (always at `User/prompts/`) and doesn't get stored anywhere that Settings Sync would replicate.

## Plan handoff issues

### `claude-handoff` says "no plans found"

**Symptom**: Running `claude-handoff` prints `No plans found in ~/.claude/plans/`.

**Cause**: No `*.md` files in `~/.claude/plans/` (other than `_next.md` which is filtered).

**Fix**: Generate a plan first — use plan mode in Claude Code to create one, then run `claude-handoff`.

### `claude-handoff` says "push failed"

**Symptom**: `claude-handoff` commits locally but the git push fails.

**Cause**: Either no remote is configured, or network/auth issue.

**Fix**:
- If no remote: `cd ~/src/claude-config && gh repo create claude-config --private --source=. --remote=origin && git push -u origin main`
- If network/auth: debug git push normally (`git remote -v`, check SSH key or token).

`claude-handoff` will keep the plan committed locally; you can push manually when the issue is resolved, and the other machine will see it on next pull.

### A plan written on one machine isn't visible on the other

**Symptom**: You ran `claude-handoff` on the laptop, but on the desktop `~/.claude/plans/_next.md` doesn't exist or has old content.

**Diagnosis**:
```bash
# On the laptop
cd ~/src/claude-config
git log --oneline -3 -- plans/_next.md
git status

# On the desktop
cd ~/src/claude-config
git log --oneline -3 -- plans/_next.md
git pull
ls -la plans/_next.md
```

**Fix**: Almost always a missed `git pull` on the desktop, or an un-pushed `git commit` on the laptop. Check both. If the plan is committed and pushed on the laptop, and the pull succeeded on the desktop, then `ls -la ~/.claude/plans/_next.md` should show the new content (via the symlink).

## Settings issues

### I keep getting prompted for the same `Bash(...)` pattern

**Symptom**: Claude Code prompts for permission on a command you use all the time.

**Fix**: Add the broad pattern to `settings.base.json` (or platform-specific file), commit, push, re-run `install.sh`.

Example: if you're getting prompted for `Bash(xcodebuild -scheme whatever -destination whatever...)`, the pattern to add is `Bash(xcodebuild:*)` which covers ALL xcodebuild invocations. It's already in `settings.mac.json` if you've pulled the latest.

### `~/.claude/settings.json` has entries I added manually and I don't want to lose them on next install

**Symptom**: You added a permission by hand to `~/.claude/settings.json` (or approved it via the prompt UI, which adds it there). You're worried install.sh will wipe it.

**Fix**: it will wipe it. Promote it to the repo first.

```bash
# 1. Find the entry in your local settings
jq '.permissions.allow' ~/.claude/settings.json | less
# 2. Copy the entry you want to keep
# 3. Edit the right settings file in the repo
vi ~/src/claude-config/settings.base.json    # or settings.mac.json / settings.windows.json
# 4. Add the entry to permissions.allow
# 5. Commit, push
# 6. Re-run install.sh — the entry is now persistent across reinstalls
bash ~/src/claude-config/install.sh
```

## "I broke something and I want to start over" — safe reset

If the install is in a weird state and you want to start clean without losing anything:

```bash
# 1. Backup everything in ~/.claude/ that isn't machine-generated
mv ~/.claude ~/.claude.saved.$(date +%s)

# 2. Re-run install from the repo
cd ~/src/claude-config
bash install.sh

# 3. If you needed anything from the saved dir (custom commands you hadn't committed,
#    project memory, etc.), cherry-pick from ~/.claude.saved.*
```

`install.sh` creates a fresh `~/.claude/` from scratch. The only thing you lose is the unsynced local state (accumulated grants, project conversation history in `projects/`, logs). Of those, only `projects/` has any value, and you can copy it back from the saved dir:

```bash
cp -R ~/.claude.saved.*/projects ~/.claude/projects
```

Delete `~/.claude.saved.*` when you're confident everything works.

## When troubleshooting doesn't help

If you've tried the relevant section and the symptom persists:

1. **Check the git log** — has the repo gotten out of sync in a way I'm not accounting for?
2. **Re-read the failing step's code** — `install.sh` and `preflight.sh` are small enough to read top-to-bottom. The failure is usually obvious once you find the relevant block.
3. **Run with `-x` for trace output**: `bash -x install.sh 2>&1 | less` shows every command as it runs.
4. **Check for silent environment issues**: `env | grep -i claude`, `env | grep -i msys`, `echo $PATH`, `which -a claude`, `which -a jq`.
5. **Ask a new Claude Code session** to help you diagnose. It can read the scripts and your shell state.

Don't be afraid to `rm -rf ~/.claude && bash install.sh` as a last resort — you won't lose anything in the repo, just the machine-local state.
