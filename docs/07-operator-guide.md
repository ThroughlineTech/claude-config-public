# Operator Guide

Host install walkthrough (Mac/Linux/Windows), new-machine checklist,
edit-sync matrix, maintenance cadence, and intercom ops reference. The
narrative version of what `install.sh` does and why.

Date: 2026-05-09. Code-true at HEAD `7f34639`.

## Prerequisites

Every machine needs:

- **git** — clone and pull the repo
- **bash** — run `install.sh` and `preflight.sh` (Git Bash on Windows)
- **jq** — merge the settings JSON files
- **Claude Code** — installed and on PATH
- **VS Code** + **GitHub Copilot** extension (optional; needed for Copilot Chat integration)
- **Symlink capability** — Mac/Linux: built in. Windows: **Developer Mode** must be on
  (Settings → System → For developers → Developer Mode: **On**). No reboot required.

### Installing jq

| Platform | Command |
|---|---|
| macOS | `brew install jq` |
| Ubuntu/Debian | `sudo apt install jq` |
| Fedora | `sudo dnf install jq` |
| Windows (winget) | `winget install jqlang.jq` |
| Windows (scoop) | `scoop install jq` |

After installing jq on Windows, **close and reopen Git Bash** so `which jq` finds the binary.

## Mac / Linux install

```bash
git clone git@github.com:<you>/claude-config.git ~/src/claude-config
cd ~/src/claude-config
bash preflight.sh
bash install.sh
source ~/.zshrc      # or ~/.bashrc
```

Verify:

```bash
ls -la ~/.claude/CLAUDE.md ~/.claude/plan-mode.md ~/.claude/brainstorm-mode.md \
        ~/.claude/commands ~/.claude/plans ~/.claude/brief-templates
# Should show six symlinks pointing into ~/src/claude-config/

jq .effortLevel ~/.claude/settings.json
# Should print "max"

which claude-handoff
# Should print /Users/you/src/claude-config/bin/claude-handoff
```

## Windows install

Windows has three gotchas Mac/Linux don't. `preflight.sh` catches all of them —
**always run preflight first** on Windows.

### Step 1: enable Developer Mode

Settings → System → For developers → Developer Mode → **On**. Allows non-admin users
to create symbolic links. Leave it on permanently; it has no other practical effect.

### Step 2: install jq

```powershell
winget install jqlang.jq
```

Then close and reopen Git Bash so the binary is on PATH.

### Step 3: clone and preflight

```bash
cd ~
mkdir -p src && cd src
git clone git@github.com:<you>/claude-config.git
cd claude-config
bash preflight.sh
```

Read the preflight output carefully. Expect:

- `[1] Platform`: Windows shell detected (MINGW64)
- `[2] Required tools`: all present (if jq is missing, step 2 was skipped)
- `[3] Symlink capability`: ✓ (if ✗, see troubleshooting below)
- `[4] Repo contents`: all expected files present
- `[5] What install.sh would back up`: warnings about existing `~/.claude/` content
- `[6] Existing settings.json analysis`: accumulated allow grants report
- `[7] VS Code (Copilot) detection`: VS Code user dir present
- `[8] Shell rc`: `~/.bashrc` found
- `[9] Git configuration`: git user name + email set

### Step 4: install

```bash
bash install.sh
```

`install.sh` automatically exports `MSYS=winsymlinks:nativestrict` before creating
symlinks. If any smoke-test failures are reported, **stop and read the error** — don't
re-run blindly.

### Step 5: pick up PATH

```bash
source ~/.bashrc
which claude-handoff
```

Should print the path to `claude-handoff` in the repo's `bin/`.

### Step 6: VS Code Copilot verification

Open VS Code → Copilot Chat → "New Chat". Type:

```
send me a test prowl
```

If a Prowl notification arrives on your phone, the full chain works: instructions
file loaded, CLAUDE.md read, Prowl API called.

### If symlinks still don't work after Developer Mode

1. **Close and reopen Git Bash.** Some installs cache the symlink capability check at startup.
2. **Manually set MSYS:**
   ```bash
   export MSYS=winsymlinks:nativestrict
   bash preflight.sh
   ```
   If `[3]` turns green, persist it: `echo 'export MSYS=winsymlinks:nativestrict' >> ~/.bashrc`
3. **Check you're not accidentally in WSL.** `uname -s` should print `MINGW64_NT-…` on
   Git Bash. WSL installs into a different `~/.claude/`.
4. **Run Git Bash as Administrator** for the one `bash install.sh` invocation. Symlinks
   created persist after the elevated shell closes.

## What `install.sh` actually does

The script is ~500 lines; this is the logical summary:

1. **Export `MSYS=winsymlinks:nativestrict`** on Windows.
2. **Create `~/.claude/`** if absent.
3. **Symlink into `~/.claude/`**: `CLAUDE.md`, `plan-mode.md`, `brainstorm-mode.md`,
   `commands/`, `plans/`, `brief-templates/`, `operation-templates/`, `agents/`.
   Existing targets backed up to `*.backup.{timestamp}` before the symlink is created.
4. **Detect platform** (`Darwin` → mac, `Linux` → linux, `MINGW*`/`MSYS*`/`CYGWIN*` → windows).
5. **Merge settings.json**: `settings.base.json` + `settings.{platform}.json` →
   `~/.claude/settings.json`. Concatenates `permissions.allow` and `permissions.deny`
   arrays; backs up the existing file first.
6. **Generate Copilot instructions files**: prepend `applyTo: "**"` frontmatter to
   `CLAUDE.md`, `plan-mode.md`, `brainstorm-mode.md` → `copilot-prompts/*.instructions.md`.
   Generated files are gitignored; source files are the single source of truth.
7. **Symlink `copilot-prompts/*.md`** into VS Code's user prompts directory if VS Code
   is detected (Mac: `~/Library/Application Support/Code/User/prompts/`, Windows:
   `%APPDATA%/Code/User/prompts/`, Linux: `~/.config/Code/User/prompts/`).
8. **Add `bin/` to PATH** by appending to `~/.zshrc` or `~/.bashrc`.
9. **Register Plane MCP server** in two places (requires `secrets/.env`):
   - Claude Code user scope (`~/.claude.json`): `command: "uvx"`, `args: ["plane-mcp-server", "stdio"]`
   - Copilot user scope (`$VSCODE_USER_DIR/mcp.json`): `command: "uv"`,
     `args: ["run", "--no-project", "<abs-path>/bin/plane-mcp-proxy.py"]` — the proxy
     filters 109 tools → 17 so Copilot's context budget is not overwhelmed (CCONF-25).
10. **Symlink `bin/` helpers into `~/bin/`**: `send-job`, `intercom-session`,
    `intercom-machines`, `intercom-repos`, `intercom-inbox-mutate`, `intercom-inbox-listener`,
    `plane-mcp-proxy.py`, `sync-copilot-prompts`.
11. **Install intercom hook**: symlink `hooks/surface-intercom-replies.sh` to
    `~/.claude/hooks/`; registered in `settings.base.json` as `UserPromptSubmit`.
12. **Windows only**: render `windows/intercom-inbox-listener.xml.template` and register
    the Task Scheduler task.
13. **Smoke tests**: verify symlinks, settings shape, MCP command values (including that
    the Copilot entry uses `uv`/`plane-mcp-proxy.py`).

## New-machine checklist

Quick form of the above for machines you've done this on before:

```bash
# 1. Clone to the canonical location
cd ~ && mkdir -p src && cd src
git clone git@github.com:<you>/claude-config.git
cd claude-config

# 2. Preflight (read-only, must pass before proceeding)
bash preflight.sh
# Must see: "Summary: N pass, M warn, 0 fail"

# 3. Install
bash install.sh
# Must end with: "✓ Install complete."

# 4. Pick up PATH
source ~/.bashrc     # or ~/.zshrc on Mac
which claude-handoff

# 5. Verify symlinks
ls -la ~/.claude/CLAUDE.md ~/.claude/commands ~/.claude/plans ~/.claude/brief-templates

# 6. Verify settings
jq '{effortLevel, allowCount: (.permissions.allow | length), denyCount: (.permissions.deny | length)}' ~/.claude/settings.json
# effortLevel: "max"; allowCount: >30; denyCount: >=7

# 7. Claude Code smoke test
# In any Claude Code session: "what's my prowl API key?"
# Should know (reads ~/.claude/CLAUDE.md → symlinked from repo)

# 8. Copilot smoke test
# VS Code → Copilot Chat → New Chat → "send me a test prowl"
```

### Preflight failure table

| Failure | Fix |
|---|---|
| `jq MISSING` | Install jq, close/reopen shell, re-run preflight |
| `ln -s result is not a symlink` (Windows) | Enable Developer Mode; restart Git Bash |
| `ln -s result is not a symlink` (Mac/Linux) | Check filesystem permissions |
| `missing: {file}` | Re-clone the repo (incomplete clone) |
| `git user.name not set globally` | `git config --global user.name "..."` |

### Install failure table

| Error | Fix |
|---|---|
| `Permission denied` on symlink | Windows: Developer Mode not on, or run Git Bash as admin |
| `jq: command not found` | Install jq, then re-run `bash install.sh` |
| `VS Code user dir not found` | Not a blocker; re-run install.sh after installing VS Code |

## Edit-sync matrix

| I edited… | On this machine I need to: | On other machines after `git pull`: |
|---|---|---|
| `CLAUDE.md` | Re-run `install.sh` | Re-run `install.sh` |
| `plan-mode.md` | Re-run `install.sh` | Re-run `install.sh` |
| `brainstorm-mode.md` | Re-run `install.sh` | Re-run `install.sh` |
| `commands/*.md` | Nothing (symlinked — edits are live) | Nothing |
| `brief-templates/*.md` | Nothing | Nothing |
| `copilot-prompts/*.prompt.md` | Nothing | Nothing |
| `settings.base.json` | Re-run `install.sh` | Re-run `install.sh` |
| `settings.mac.json` | Re-run `install.sh` on Mac | Re-run `install.sh` on Mac machines |
| `settings.windows.json` | Re-run `install.sh` on Windows | Re-run `install.sh` on Windows machines |
| `install.sh` or `preflight.sh` | Re-run install.sh | Re-run install.sh |
| `bin/*` | Nothing (symlinked via `~/bin/`) | Nothing |
| `plans/*.md` | Nothing (symlinked) | Nothing |
| `docs/**` | Nothing | Nothing |

**Rule of thumb**: if the file is symlinked, edits are live. If the file is
regenerated by `install.sh` (`~/.claude/settings.json`, `copilot-prompts/*.instructions.md`),
re-run `install.sh`.

## Specific edit scenarios

### Add a new rule to CLAUDE.md

Edit `CLAUDE.md`. Re-run `install.sh` (regenerates Copilot instructions file). Commit
and push. On other machines: pull, re-run `install.sh`.

### Add or tweak a slash command

Edit `commands/{name}.md` (or create a new file there). Commit and push. No `install.sh`
re-run needed — `commands/` is symlinked so edits are live immediately on the editing
machine; other machines pick up the change after `git pull`.

After shipping a command change, sync its Copilot counterpart so Copilot Chat stays
behaviorally current:

```bash
# From the repo root — syncs one command
bash bin/sync-copilot-prompts commands/<name>.md

# Or in Copilot Chat using the sync-claude-command prompt
# (this is a Copilot prompt in copilot-prompts/, NOT a Claude Code slash command)

# Refresh all at once
bash bin/sync-copilot-prompts --all
```

Commit the updated `copilot-prompts/<name>.prompt.md` in the same commit as the
command change.

Alias files (`tn.md`, `tch.md`, etc.) do not need syncing — their Copilot
counterparts are thin delegates that don't change when the canonical command changes.

### Add a permission allow (all machines)

Edit `settings.base.json`, add entry to `permissions.allow`. Commit and push. Re-run
`install.sh` on every machine.

### Add a permission allow (Mac only)

Edit `settings.mac.json`. Commit and push. Re-run `install.sh` on Mac machines only.

### Hand off a plan to another machine

```bash
# On the machine where the plan was written
claude-handoff                   # picks the most recent plan
# or: claude-handoff some-name.md

# On the receiving machine
cd ~/src/claude-config && git pull
# Then in any Claude Code session: "execute the plan in ~/.claude/plans/_next.md"
```

### Rotate the Prowl API key

1. Generate new key at prowlapp.com
2. Edit `CLAUDE.md` — replace the old key
3. Commit and push
4. On every machine: `git pull && bash install.sh`
5. Test: "send me a test prowl" in both Claude Code and Copilot Chat
6. Invalidate the old key once the new one is confirmed working

### Rotate the Plane API key

Edit `PLANE_API_KEY` in `secrets/.env` (gitignored — local edit only). Re-run
`install.sh`. Both `~/.claude.json` and VS Code `mcp.json` get the new value in one
pass. Repeat on each machine separately (secrets don't sync via git).

## Maintenance cadence

### Daily — nothing

The system is designed so daily use costs no maintenance. The only background activity
is your local `~/.claude/settings.json` accumulating one-shot permission grants — those
are fine until you review them monthly.

### Weekly — 2 minutes

Pull on every machine you've used this week:

```bash
cd ~/src/claude-config && git pull
# If the pull touched CLAUDE.md, plan-mode.md, brainstorm-mode.md, or settings.*.json:
bash install.sh
```

Skim recent plans:

```bash
ls -t ~/.claude/plans/*.md | head -5
```

### Monthly — 15-30 minutes

**1. Mine accumulated permission grants.**

```bash
# Count total allow entries
jq '.permissions.allow | length' ~/.claude/settings.json

# Show entries added since last install
diff <(jq -r '.permissions.allow[]' ~/.claude/settings.json | sort) \
     <(jq -r '(.permissions.allow + .permissions.allow) | .[]' \
         ~/src/claude-config/settings.base.json \
         ~/src/claude-config/settings.mac.json 2>/dev/null | sort) \
     | grep '^<'
```

Promote broad patterns (e.g. `Bash(tool-name:*)`) to `settings.base.json` or the
platform file. Ignore one-shot commands with specific paths, IDs, or timestamps.

**2. Delete old backups.**

```bash
ls -la ~/.claude/*.backup.* ~/.claude/*/*.backup.* 2>/dev/null
# Safe to delete after a week:
rm -rf ~/.claude/commands.backup.* ~/.claude/plans.backup.* \
       ~/.claude/brief-templates.backup.*
rm ~/.claude/CLAUDE.md.backup.* ~/.claude/plan-mode.md.backup.*
# Keep settings.json.backup.* until you've mined it, then delete
```

**3. Verify machines are in sync.**

```bash
# On each machine:
cd ~/src/claude-config && git log --oneline -5
```

Same top commit = in sync.

### Semi-annual — 30-60 minutes

- Read through `docs/state-of-the-system/` — anything wrong, outdated, or missing?
- Audit `commands/` — any commands never used, or behaviors you work around?
- Audit `brief-templates/` — which templates have you actually used?
- Check `permissions.deny` — any new "never let an agent do this" rules from six months
  of real use?

### Annual or on major workflow change

- Is the symlink/install/settings model still the right abstraction?
- Are you actually using the ticket workflow? The delegation system?
- Is `CLAUDE.md` still short (< 100 lines of actual content)?
- Have tools changed in ways that make workflow components obsolete?

### Red flags that need immediate attention

- `jq .effortLevel ~/.claude/settings.json` fails or returns null → settings merge broke;
  re-run `bash install.sh -x` to diagnose.
- Symlinks in `~/.claude/` are broken links → repo moved or deleted; re-clone and
  re-run install.sh.
- Permission grants ballooning (100+ in a week) → missing a broad pattern in `settings.base.json`.
- Copilot suddenly not loading instructions → re-run `install.sh` (VS Code updates can
  move the prompts directory).

### Minimum viable maintenance

Re-run `bash install.sh` on each machine after any `git pull` that touched `CLAUDE.md`,
`plan-mode.md`, `brainstorm-mode.md`, or a settings file. That's the only load-bearing
maintenance task. Everything else is polish.

## Intercom ops reference

The intercom subsystem handles cross-machine job dispatch via MQTT. claude-config owns
the dispatcher side (helpers in `bin/`, hook in `hooks/`, Task Scheduler XML in
`windows/`). The receiver is provisioned separately from `claude-intercom/receiver/`.

### Stack overview

```
┌──────────────────────────────────────────┐
│  DISPATCHER (Windows workstation)        │
│  - Claude Code session                   │
│  - ~/bin/send-job, intercom-session,     │
│    intercom-machines, intercom-repos     │
│  - ~/bin/intercom-inbox-listener         │
│    (Task Scheduler — appends replies     │
│    to ~/.local/state/intercom/inbox.jsonl│
│  - ~/.claude/hooks/                      │
│    surface-intercom-replies.sh           │
│    (UserPromptSubmit — surfaces unread   │
│    replies at top of each response)      │
└──────────────┬───────────────────────────┘
               │  mosquitto_pub/sub
               │  topics: jobs/<machine>/<repo>
               │           replies/<machine>/<repo>
               ▼
┌──────────────────────────────────────────┐
│  BROKER (MQTT, LXC or VPS)              │
│  - mosquitto; auth via user/pass         │
│  - Accessible over Tailscale or VPN      │
└──────────────┬───────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────┐
│  RECEIVER (Mac mini or Linux server)     │
│  - claude-intercom/receiver/mac/         │
│  - Subscribes to jobs/#                  │
│  - Runs claude -p against local repo     │
│  - Publishes result to replies/#         │
└──────────────────────────────────────────┘
```

### Creds file

All dispatcher helpers read `~/.config/intercom/creds` at runtime:

```bash
MQTT_HOST=100.x.y.z        # broker Tailscale IP or hostname
MQTT_PORT=1883
MQTT_USER=dispatcher
MQTT_PASS=<password>
```

`install.sh` creates this file (chmod 600) on first run if you provide values at the
prompt. To create or edit manually:

```bash
mkdir -p ~/.config/intercom
cat > ~/.config/intercom/creds <<'EOF'
MQTT_HOST=100.x.y.z
MQTT_PORT=1883
MQTT_USER=dispatcher
MQTT_PASS=yourpassword
EOF
chmod 600 ~/.config/intercom/creds
```

### Task Scheduler management (Windows)

```powershell
# Check status
schtasks /Query /TN intercom-inbox-listener

# Start manually
schtasks /Run /TN intercom-inbox-listener

# Stop
schtasks /End /TN intercom-inbox-listener

# Unregister
schtasks /Delete /TN intercom-inbox-listener /F

# Re-register (e.g. after changing the XML template)
schtasks /Create /XML "C:\Users\<you>\src\claude-config\windows\intercom-inbox-listener.xml.rendered" /TN intercom-inbox-listener /F
```

To re-render the XML template (new machine or template change):

```bash
cd ~/src/claude-config
sed "s|{{WINDOWS_USER}}|${USERNAME}|g" windows/intercom-inbox-listener.xml.template \
  > windows/intercom-inbox-listener.xml.rendered
schtasks /Create /XML "$(cygpath -w windows/intercom-inbox-listener.xml.rendered)" /TN intercom-inbox-listener /F
```

### Hook troubleshooting

**Hook not firing:**

```bash
ls -la ~/.claude/hooks/surface-intercom-replies.sh
jq '.hooks.UserPromptSubmit' ~/.claude/settings.json
```

If the hook entry is missing, re-run `./install.sh` to regenerate `~/.claude/settings.json`.

**Replies not appearing despite listener running:**

```bash
ls -la ~/.local/state/intercom/inbox.jsonl
cat ~/.local/state/intercom/inbox.cursor
# Reset cursor to re-read all replies (will re-surface everything):
rm ~/.local/state/intercom/inbox.cursor
```

**Replies appear then stop (cursor stuck):**

Torn/incomplete line at the end of `inbox.jsonl` — listener was killed mid-write.
The hook stays at the last clean line until the listener appends a complete one.

```bash
tail -5 ~/.local/state/intercom/inbox.jsonl | jq . 2>&1
# If the last line errors, it's torn — wait for the listener to finish
```

**Large replies going to files instead of inline:**

`intercom-inbox-mutate` auto-archives replies over 50 lines to `~/.intercom/responses/`.
The hook surfaces a pointer line. Read the file directly.

### MQTT password rotation

1. Update the broker's password file.
2. Edit `MQTT_PASS` in `~/.config/intercom/creds` on each dispatcher machine.
3. Restart the Task Scheduler listener on Windows:
   ```powershell
   schtasks /End /TN intercom-inbox-listener
   schtasks /Run /TN intercom-inbox-listener
   ```
4. Test with `/machines` — should respond within 2–3 seconds.

### Slash commands for day-to-day dispatch

- `/register` — register this machine as a receiver candidate
- `/send` — send a job to a remote machine
- `/draft` — draft a job without sending
- `/machines` — list known machines and their status
- `/repos` — list known repos on a machine

### Pointers

- Runtime source: [claude-intercom](https://github.com/danrichardson/claude-intercom)
- Day-to-day usage: claude-intercom/docs/dogfooding-guide.md
- Session state: `~/.config/intercom/session`
- Inbox: `~/.local/state/intercom/inbox.jsonl`
- Large reply archive: `~/.intercom/responses/`
