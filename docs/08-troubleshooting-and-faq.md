# Troubleshooting and FAQ

Symptom-based troubleshooting (install, Claude Code, Copilot, plan handoff, settings,
intercom) and frequently asked questions (general, installation, daily use, delegation,
secrets, sync, advanced).

Date: 2026-05-09. Code-true at HEAD `7f34639`.

---

## Troubleshooting

### Install failures

#### `jq: command not found` during settings merge

**Symptom**: `install.sh` prints `⚠ jq not installed; skipping settings merge.`

**Fix**: install jq, close and reopen your shell, re-run `install.sh`.

| Platform | Command |
|---|---|
| macOS | `brew install jq` |
| Linux (Debian/Ubuntu) | `sudo apt install jq` |
| Linux (Fedora) | `sudo dnf install jq` |
| Windows (winget) | `winget install jqlang.jq` |
| Windows (scoop) | `scoop install jq` |

After installing on Windows, close all Git Bash windows and reopen so the new binary is on PATH.

#### Preflight `[3]` reports "ln -s ran but the result is not a symlink" (Windows)

**Cause**: By default, Git Bash creates "fake" MSYS symlinks — regular files that MSYS
interprets as symlinks but Windows-native apps (Claude Code, VS Code, `[ -L ]` in bash)
see as regular files.

**Fix**:

```bash
export MSYS=winsymlinks:nativestrict
bash preflight.sh
```

Preflight should now report `[3] ✓ ln -s creates real symlinks`. Persist:

```bash
echo 'export MSYS=winsymlinks:nativestrict' >> ~/.bashrc
```

Also requires Windows Developer Mode on (Settings → System → For developers). Without it
the OS blocks symlink creation even with `nativestrict`.

`install.sh` exports this automatically — the issue only surfaces if you're running
preflight before install on an older version of the script.

#### "Permission denied" on symlink creation

**Cause**:
- Mac/Linux: you don't own `~/.claude/` (rare).
- Windows: Developer Mode is off AND you're not running as admin.

**Fix**:
- Mac/Linux: `sudo chown -R $USER ~/.claude` then re-run install.
- Windows: turn on Developer Mode (permanent), OR right-click Git Bash → "Run as
  administrator" for the one `bash install.sh` invocation.

#### Smoke tests fail at end of install.sh

**Symptom**: install runs through most steps then prints `✗ {something} not symlinked`.

Common causes:
- Multiple symlinks missing: something interrupted the script (Ctrl+C, terminal closed) → re-run.
- One specific symlink missing: that file may not exist in the repo → `ls ~/src/claude-config/{path}`.
- `settings.json effortLevel != max`: jq merge didn't run → verify `settings.base.json`
  has `"effortLevel": "max"`, run the jq command manually to debug.

#### install.sh says it's done but symlinks don't resolve

**Cause**: symlinks point at a path that no longer exists (repo was moved after install).

**Fix**: re-run `install.sh` from the current repo location. The `DOTFILES="$(cd "$(dirname "$0")" && pwd)"` line captures the absolute path at install time.

#### install.sh refuses: "Refusing to run from a git worktree"

**Cause**: You ran it from `.worktrees/<branch>/` or a similar linked worktree. If it
proceeded, every symlink in `~/.claude/` would point into the worktree and break the
moment the worktree is reaped after `/ticket-ship`.

**Fix**: run install.sh from the main checkout, as the error message directs:

```bash
bash /path/to/claude-config/install.sh
```

---

### Claude Code issues

#### Claude Code doesn't know about Prowl

**Diagnosis**:

```bash
ls -la ~/.claude/CLAUDE.md
cat ~/.claude/CLAUDE.md | head -20
```

Common causes:
1. `~/.claude/CLAUDE.md` is not a symlink, or is broken → re-run `install.sh`.
2. Symlink points at empty or wrong file → `readlink ~/.claude/CLAUDE.md`, verify the target.
3. Project-level `CLAUDE.md` overrides the global one → `cat $(pwd)/CLAUDE.md`.
4. Session was started before the symlink was created → start a new session.

#### Claude Code prompts for something I thought I allowed globally

**Cause**: `install.sh` regenerated `~/.claude/settings.json` and wiped the accumulated grant.

**Fix**: add the broad pattern to `settings.base.json` (not just the local file):

```bash
# Check current allows
jq '.permissions.allow' ~/.claude/settings.json | grep -i <command>
# Add the broad pattern (e.g. Bash(git:*)) to the repo:
vi ~/src/claude-config/settings.base.json
# Commit, push, re-run install.sh
```

#### `/ticket-new` says "ticket config not found"

**Cause**: project hasn't been bootstrapped with `/ticket-install`.

**Fix**: run `/ticket-install` in the project, answer the prompts, retry.

---

### Copilot issues

#### "send me a test prowl" doesn't work in Copilot Chat

**Diagnosis sequence**:

1. Verify the instructions file is in the right place:
   ```bash
   # Mac
   ls -la "$HOME/Library/Application Support/Code/User/prompts/claude-global.instructions.md"
   # Windows Git Bash
   ls -la "$APPDATA/Code/User/prompts/claude-global.instructions.md"
   ```

2. Verify it has the right frontmatter:
   ```bash
   head -5 ~/src/claude-config/copilot-prompts/claude-global.instructions.md
   # Should start with: --- / applyTo: "**" / ---
   ```

3. Verify Copilot Chat is in **Agent mode**, not Ask mode (toggle in the chat input area).

4. **Start a NEW chat conversation** (click "+" or "New Chat") — existing sessions may not
   pick up the instructions.

5. Check CLAUDE.md still has the Prowl key:
   ```bash
   grep -A 5 "Prowl" ~/src/claude-config/CLAUDE.md
   ```

#### VS Code shows deprecation warning on settings.json instruction key

**Symptom**: `"github.copilot.chat.codeGeneration.instructions"` in `settings.json` is squiggled.

**Fix**: Remove it. The `User/prompts/claude-global.instructions.md` file is the current mechanism.

#### VS Code Settings Sync pushed a Mac absolute path to Windows

**Cause**: an older version of this repo stored an absolute file path in VS Code `settings.json`.
Settings Sync replicated it to Windows where it's invalid.

**Fix**: Remove the key from VS Code `settings.json` on both machines. The instructions-file
mechanism doesn't store paths anywhere Sync can replicate.

#### Plane MCP shows a cross-OS spawn error (ENOENT)

**Symptom**: VS Code MCP logs show `spawn C:\Users\...\uvx.exe ENOENT` on macOS/Linux (or a
POSIX path failing on Windows).

**Cause**: stale cross-OS MCP config, or config was copied/synced from another machine.

**Fix**: re-run `install.sh` on the affected machine, then restart VS Code/Copilot Chat.

Note: Claude Code uses `command: "uvx"` (host-agnostic). Copilot uses `command: "uv"` with
`bin/plane-mcp-proxy.py` (see CCONF-25). Both entries are rewritten by install.sh to
host-appropriate values.

---

### Plan handoff issues

#### `claude-handoff` says "no plans found"

**Cause**: no `*.md` files in `~/.claude/plans/` (other than `_next.md`, which is filtered).

**Fix**: generate a plan first using plan mode in Claude Code, then run `claude-handoff`.

#### `claude-handoff` says "push failed"

**Cause**: no remote configured, or network/auth issue.

**Fix**:
- No remote: `cd ~/src/claude-config && gh repo create claude-config --private --source=. --remote=origin && git push -u origin main`
- Network/auth: debug git push normally (`git remote -v`, check SSH key or token).

The plan is committed locally; push manually when the issue resolves.

#### A plan on one machine isn't visible on another

**Diagnosis**:

```bash
# On the source machine
cd ~/src/claude-config && git log --oneline -3 -- plans/_next.md && git status

# On the target machine
cd ~/src/claude-config && git log --oneline -3 -- plans/_next.md && git pull && ls -la plans/_next.md
```

Almost always a missed `git pull` on the target, or an un-pushed commit on the source.

---

### Settings issues

#### Prompted repeatedly for the same `Bash(...)` pattern

**Fix**: add the broad pattern to `settings.base.json`, commit, push, re-run `install.sh`.
Example: `Bash(xcodebuild:*)` covers all xcodebuild invocations.

#### Manually added entries vanish after reinstall

**Cause**: `install.sh` regenerates `~/.claude/settings.json`. Manual edits to Layer 2 are
always wiped on next install.

**Fix**: promote entries to the repo before reinstalling:

```bash
jq '.permissions.allow' ~/.claude/settings.json | less   # find the entry
vi ~/src/claude-config/settings.base.json                # add it
git commit && git push
bash ~/src/claude-config/install.sh
```

---

### Safe reset ("I broke something and want to start over")

```bash
# 1. Backup current ~/.claude/
mv ~/.claude ~/.claude.saved.$(date +%s)

# 2. Re-run install
cd ~/src/claude-config && bash install.sh

# 3. Cherry-pick anything you need from the saved dir
# Conversation history is the main thing worth recovering:
cp -R ~/.claude.saved.*/projects ~/.claude/projects
```

Delete `~/.claude.saved.*` when you're confident everything works.

---

### Intercom troubleshooting

#### Install-time failures

| Symptom | Cause | Fix |
|---|---|---|
| `mosquitto_pub not found` warning | mosquitto-clients not installed | `brew install mosquitto` / `winget install cedalo.mosquitto` / `apt install mosquitto-clients` |
| `schtasks` fails on Windows | Non-admin, or Task Scheduler service stopped | Run Git Bash as admin for install, or register task manually |
| `~/.config/intercom/creds` missing after install | Non-interactive mode, or Ctrl+C at prompt | Create manually (see 07-operator-guide.md → Creds file) |
| Hook missing from settings.json | jq was absent during settings merge | Install jq, re-run `install.sh` |

#### Runtime failures

| Symptom | Cause | Fix |
|---|---|---|
| `/machines` returns no responders | Broker unreachable, creds wrong, receiver not running | Check creds; ping broker; check receiver service |
| Replies not surfacing in Claude Code | Hook not installed or inbox.jsonl empty | `ls ~/.claude/hooks/surface-intercom-replies.sh`; check Task Scheduler status |
| Inbox cursor stuck | Torn line at end of inbox.jsonl (listener killed mid-write) | Listener will complete the line; cursor auto-advances. Or `rm ~/.local/state/intercom/inbox.cursor` to reset |
| Old intercom MCP entry causing VS Code errors | Left over from HTTP-era install | Re-run `install.sh` — it removes `mcpServers.intercom` via `jq del()` |

For ops procedures (creds rotation, Task Scheduler management), see
[07-operator-guide.md](07-operator-guide.md). For runtime issues (messages not routing,
stale peers), see the claude-intercom dogfooding guide.

---

### General debugging checklist

If none of the above matches:

1. `git log --oneline -5` — is the repo in sync?
2. `git status` — uncommitted changes?
3. `bash -x install.sh 2>&1 | less` — trace every step.
4. `env | grep -i msys; echo $PATH; which -a jq; which -a claude` — environment sanity.
5. `rm -rf ~/.claude && bash install.sh` as last resort — you lose only machine-local state,
   not anything in the repo.

---

## FAQ

### General

#### What is this repo, in one sentence?

Personal dotfiles for Claude Code and Copilot Chat, plus a universal ticket workflow backed
by self-hosted Plane, plus a cross-model delegation system, all syncable between machines via git.

#### Why is it private?

`CLAUDE.md` contains a Prowl API key, and `plans/` contains in-progress design work on
various projects. If you want to publish the workflow (commands, templates, install.sh, docs)
without those, split into `claude-config-public` (workflow) + `claude-config-private` (secrets
and plans), with `install.sh` knowing how to find both.

---

### Installation

#### Do I need to re-run `install.sh` after every git pull?

Only if the pull touched `CLAUDE.md`, `plan-mode.md`, `brainstorm-mode.md`, or a
`settings.*.json` file. Everything else is live via symlinks.
See [07-operator-guide.md](07-operator-guide.md) for the full matrix.

#### Is `install.sh` safe to re-run?

Yes — it's idempotent. Leaves correct symlinks alone, replaces wrong ones (with backup),
regenerates settings and instructions files, re-runs smoke tests. Worst case: 3-second no-op.

#### I ran install.sh and my accumulated permission grants are gone. Are they lost?

No — they're in `~/.claude/settings.json.backup.{timestamp}`. Mine it for broad patterns
worth promoting to `settings.base.json`.

#### Can I run this on a machine that already has Claude Code set up?

Yes. `install.sh` backs up any existing `~/.claude/CLAUDE.md`, `commands/`, `plans/`,
`brief-templates/`, and `settings.json` to `*.backup.{timestamp}` before replacing them.
Nothing is deleted; everything is recoverable.

#### Does this work on WSL?

It should — `install.sh` treats WSL as Linux and installs into the WSL filesystem's
`~/.claude/`. Claude Code inside WSL will see it; Claude Code on Windows-native won't.
To use both, install twice (once in WSL, once in Git Bash).

---

### Daily use

#### How do I bootstrap a new project for tickets?

In the project directory, start a Claude Code session, run `/ticket-install`. The Plane
backend is the default (and only supported) path when the Plane MCP server is reachable.
The Markdown backend is legacy — supported for existing projects that haven't migrated but
new projects should use Plane.

#### How do I create a new ticket?

In any Plane-bootstrapped project: `/ticket-new "short description"`.

#### How do I see what's in flight?

`/ticket-list` in the project. For a single ticket's full lifecycle, `/ticket-status PROJ-N`.

#### How do I edit the global instructions (CLAUDE.md)?

Edit `~/src/claude-config/CLAUDE.md`. Re-run `install.sh` (regenerates Copilot instructions).
Commit and push. On other machines: `git pull && bash install.sh`.

#### Can I have project-specific instructions?

Yes — create `CLAUDE.md` in the project root. Claude Code reads it in addition to the
global one; project rules take precedence on conflicts.

#### Can I add a custom slash command for one project?

Yes — put it in `.claude/commands/` inside the project (not `~/.claude/commands/`).
Project-scoped commands shadow user-scoped ones with the same name.

---

### Cross-model delegation

#### Why can't Claude Code call Gemini directly?

No API bridge from Claude Code into VS Code Copilot Chat. The handoff goes through the
filesystem via a brief file. See `commands/ticket-delegate.md` for the mechanics and
`brief-templates/` for the brief formats.

#### Do I have to use Gemini specifically?

No. Any model in Copilot Chat can execute a brief (Gemini, GPT, Claude, whatever is available).
The brief format is model-agnostic.

#### Can I review Claude Code's work with another Claude Code session?

Technically yes, but it defeats the purpose — two Claude Code sessions will tend to agree
because they're the same model with the same biases.

---

### Secrets and privacy

#### What if my Prowl key leaks?

Rotate it: update `CLAUDE.md`, commit, push, re-install on every machine, test, then
invalidate the old key at prowlapp.com. Blast radius of a leaked key: random people can
spam your phone with fake notifications — annoying but not catastrophic.

#### How do I handle additional secrets I don't want in the repo?

Use `secrets/` (gitignored) — it already stores `PLANE_BASE_URL`, `PLANE_API_KEY`,
`PLANE_WORKSPACE_SLUG`. For other secrets, create `secrets/.env.local` or a similar
gitignored file, and reference it from `CLAUDE.md`.

---

### Sync and backup

#### What happens if I edit a plan on both machines at once?

Git will refuse the pull with a conflict. Resolve like any other conflict. `_next.md`
is the main collision risk — `claude-handoff` always overwrites it intentionally, so
whichever machine pushed last wins.

#### I lost the repo on one machine. How do I recover?

```bash
git clone git@github.com:<you>/claude-config.git ~/src/claude-config
cd ~/src/claude-config && bash install.sh
```

The GitHub remote is the authoritative copy. Losing one machine's clone is a non-event.

#### Should I back up the repo somewhere other than GitHub?

GitHub is fine for a private repo. The repo is small (< 10 MB). If you're paranoid, clone
to an external drive occasionally.

---

### Advanced

#### Can I use this with Cursor / Aider / other editors?

`CLAUDE.md` and ticket files are plain markdown — any tool that reads them will work.
The slash commands are Claude-Code-specific. The Copilot prompts are VS-Code-specific.
Cursor has its own rules system (`.cursorrules`) which you could generate from `CLAUDE.md`
the same way install.sh generates the Copilot instructions file.

#### Can I share this with a colleague?

Yes, with caveats: they'd need to fork it, remove your Prowl key from `CLAUDE.md`, adapt
the settings files to their platform, and set up their own Plane instance (or disable the
Plane wiring). The infrastructure is transferable; the specific secrets and preferences are not.

#### What happens when Claude Code updates and breaks a slash command format?

Edit the affected command file in `commands/` to match the new format. Commit, push, pull
on other machines. Because commands are symlinked, every machine picks up the fix without
a reinstall.

#### Can I run multiple versions of the repo?

Not recommended — the symlinks in `~/.claude/` all point at whatever path `install.sh`
was last run from. To test a branch without affecting the installed version, use a worktree
(`git worktree add ../claude-config-test some-branch`) and don't run `install.sh` from it.

#### How do I add a new ticket command?

Create `commands/ticket-yourcommand.md` using existing commands as the format guide. Commit,
push, pull on other machines. Available in Claude Code in every project as `/ticket-yourcommand`.

#### How do I add a new brief template?

Create `brief-templates/{phase}.md`. Update `commands/ticket-delegate.md` to know about
the phase (add to the phase-specific preconditions table). Commit, push, pull. No reinstall
needed — templates are symlinked.
