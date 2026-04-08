# Adding a New Machine

Quick checklist for setting up `claude-config` on a machine you haven't used before. For the full walkthrough with explanations, see [01-install.md](01-install.md).

## Prerequisites (install before running this checklist)

- **git**
- **bash** (Git Bash on Windows)
- **jq** (`brew install jq` / `winget install jqlang.jq` / `apt install jq`)
- **Claude Code** — the agent itself
- **VS Code** + **GitHub Copilot** extension (if you want Copilot integration)
- **Windows only**: Developer Mode enabled (Settings → System → For developers → Developer Mode: On)

## The checklist

```bash
# 1. Clone to the canonical location
cd ~
mkdir -p src && cd src
git clone git@github.com:<you>/claude-config.git
cd claude-config

# 2. Run preflight (read-only)
bash preflight.sh
# Read the output. Must see "Summary: N pass, M warn, 0 fail" to proceed.
# If any failures: fix them and re-run preflight.

# 3. Install (idempotent, safe to re-run)
bash install.sh
# Reads each step. Must end with "✓ Install complete."

# 4. Pick up the new PATH
source ~/.bashrc      # or ~/.zshrc on Mac
which claude-handoff  # confirm it resolves to a path in ~/src/claude-config/bin

# 5. Verify symlinks landed
ls -la ~/.claude/CLAUDE.md ~/.claude/commands ~/.claude/plans ~/.claude/brief-templates
# All four should be symlinks pointing into ~/src/claude-config/

# 6. Verify settings regenerated correctly
jq '{effortLevel, allowCount: (.permissions.allow | length), denyCount: (.permissions.deny | length)}' ~/.claude/settings.json
# effortLevel should be "max"
# allowCount should be >30 (depends on platform)
# denyCount should be >=7

# 7. Smoke test Claude Code
# In any Claude Code session: "what's my prowl API key?"
# Claude Code should know (reads the symlinked ~/.claude/CLAUDE.md which points at the repo's CLAUDE.md)

# 8. Smoke test Copilot Chat (if you have VS Code + Copilot)
# Open VS Code, open Copilot Chat, click "New Chat", pick any model
# Type: "send me a test prowl"
# If a notification arrives on your phone, the full chain works
```

## If preflight reports failures

| Failure | Fix |
|---|---|
| `jq MISSING` | Install jq, close and reopen your shell, re-run preflight |
| `ln -s result is not a symlink` (Windows) | Enable Developer Mode in Windows Settings; restart Git Bash; re-run preflight |
| `ln -s result is not a symlink` (Mac/Linux) | Shouldn't happen. Check filesystem permissions. |
| `missing: {file}` (repo contents check) | Your git clone is incomplete or corrupted. Re-clone. |
| `git user.name not set globally` | `git config --global user.name "Your Name"` and `git config --global user.email "you@example.com"` |

## If install reports failures

Read the exact error. Common causes:

- **"Permission denied" on symlink creation** — Mac/Linux: check you own `~/.claude/`. Windows: Developer Mode not on, or run Git Bash as admin.
- **"jq: command not found" on the settings merge step** — jq wasn't installed when install.sh ran. Install it, re-run `bash install.sh`.
- **"VS Code user dir not found"** — VS Code isn't installed, or is installed in a non-standard location. Not a blocker; you just won't have Copilot integration on this machine until VS Code is installed and you re-run `install.sh`.

## After install — optional finishing steps

### Claude Code: verify you can use the ticket commands in a real project

```bash
cd ~/src/some-existing-project-or-new-project
# Start a Claude Code session in that directory
/ticket-install      # bootstraps the project if not already done
/ticket-new "test ticket to verify the universal commands work on this machine"
/ticket-list         # should show the test ticket
```

Delete the test ticket if you created one just for verification.

### Copilot: wire up the Prowl test

If the "send me a test prowl" test in step 8 didn't work, three common fixes:

1. **Check that the instructions file landed in the right place:**
   ```bash
   ls -la "$HOME/Library/Application Support/Code/User/prompts/"   # Mac
   ls -la "$APPDATA/Code/User/prompts/"                            # Windows Git Bash
   ```
   Should show `claude-global.instructions.md` as a symlink.

2. **Verify the file has the right frontmatter:**
   ```bash
   head -5 ~/src/claude-config/copilot-prompts/claude-global.instructions.md
   ```
   Should start with `---\napplyTo: "**"\n---`. If not, re-run `install.sh`.

3. **Make sure Copilot Chat is in "Agent" mode, not "Ask" mode.** There's a toggle in the chat input area. Ask mode won't execute tool calls.

### Decide whether to mine the settings.json backup

After install.sh runs, your pre-existing `~/.claude/settings.json` (if any) is at `~/.claude/settings.json.backup.{timestamp}`. It may contain accumulated permission grants from daily work that you want to preserve. See [07-editing-and-syncing.md](07-editing-and-syncing.md) for how to promote them into `settings.base.json` / `settings.mac.json` / `settings.windows.json`.

Don't rush this. Use the machine normally for a few days first. If you find yourself getting prompted for grants you don't recognize, check the backup to see if there's a pattern worth promoting. Otherwise, leave the backup alone and delete it after a week or two.

### Historical plans migration

If the machine had a pre-existing `~/.claude/plans/` directory with plans that aren't in the synced repo yet, they'll be in `~/.claude/plans.backup.{timestamp}/` after install.sh runs. To migrate them into the synced repo:

```bash
# See which backup plans are not in the repo
for f in ~/.claude/plans.backup.*/*.md; do
  name=$(basename "$f")
  [ -e ~/src/claude-config/plans/"$name" ] || echo "UNIQUE: $f"
done

# Copy the unique ones in
for f in ~/.claude/plans.backup.*/*.md; do
  name=$(basename "$f")
  [ -e ~/src/claude-config/plans/"$name" ] || cp "$f" ~/src/claude-config/plans/
done

# Commit and push
cd ~/src/claude-config
git add plans/
git commit -m "Migrate historical plans from $(hostname)"
git push
```

After this, the other machines will see the new plans on their next `git pull`.

## Total time

About 5 minutes, excluding prerequisite installs. Git clone + preflight + install + source rc = well under a minute of actual "typing." The rest is just reading the output to make sure nothing surprising happened.
