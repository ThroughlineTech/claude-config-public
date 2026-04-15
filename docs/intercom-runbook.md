# Intercom Runbook (MQTT era)

Operational reference for the intercom subsystem. Day-to-day usage (sending messages, listing peers, drafting prompts) lives in the runtime repo's [dogfooding guide](https://github.com/danrichardson/claude-intercom/blob/main/docs/dogfooding-guide.md). This document covers install-time and ops concerns that are claude-config's responsibility.

## Stack overview

Three roles, each running on a different machine:

```
┌──────────────────────────────────────────┐
│  DISPATCHER (Windows workstation)        │
│  - Claude Code session                   │
│  - ~/bin/send-job, intercom-machines,    │
│    intercom-repos, intercom-session      │
│  - ~/bin/intercom-inbox-listener         │
│    (runs under Task Scheduler, appends   │
│    replies to inbox.jsonl)               │
│  - ~/.claude/hooks/                      │
│    surface-intercom-replies.sh           │
│    (UserPromptSubmit hook surfaces        │
│    unread replies at top of response)    │
└──────────────┬───────────────────────────┘
               │  mosquitto_pub / mosquitto_sub
               │  topics: jobs/<machine>/<repo>
               │           replies/<machine>/<repo>
               │           control/registry/query
               ▼
┌──────────────────────────────────────────┐
│  BROKER (MQTT server, e.g. LXC or VPS)  │
│  - mosquitto (or compatible)             │
│  - Auth via username/password            │
│  - Accessible over Tailscale or VPN      │
└──────────────┬───────────────────────────┘
               │  mosquitto_sub / mosquitto_pub
               ▼
┌──────────────────────────────────────────┐
│  RECEIVER (Mac mini or Linux server)     │
│  - intercom-receiver (from claude-intercom
│    receiver/mac/ — separate ticket)      │
│  - Subscribes to jobs/<machine>/<repo>   │
│  - Runs claude -p against local repo     │
│  - Publishes result to replies/#         │
└──────────────────────────────────────────┘
```

claude-config is responsible for the dispatcher side: helpers in `bin/`, hook in `hooks/`, Task Scheduler XML in `windows/`, and `install.sh` wiring. The receiver is provisioned separately (see claude-intercom/receiver/mac/).

## Creds file layout

All dispatcher helpers read `~/.config/intercom/creds` at runtime:

```bash
MQTT_HOST=100.x.y.z        # broker Tailscale IP or hostname
MQTT_PORT=1883              # default MQTT port (1883 plaintext, 8883 TLS)
MQTT_USER=dispatcher        # MQTT username
MQTT_PASS=<password>        # MQTT password
```

`install.sh` creates this file (chmod 600) on first run if you provide values at the prompt. On subsequent runs it's left alone. Create or edit it manually if the prompt was skipped:

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

## ~/bin/ symlink mechanics

`install.sh` symlinks every file in `claude-config/bin/` into `~/bin/` using the same idempotent `link()` helper that manages `~/.claude/` symlinks. This means:

- Editing `~/src/claude-config/bin/send-job` is live immediately — `~/bin/send-job` is a symlink.
- Re-running `install.sh` after a `git pull` is idempotent (existing correct symlinks are reported as already linked).
- New helpers added to `bin/` are automatically linked on the next install run.

Verify the links are in place:

```bash
ls -la ~/bin/send-job ~/bin/intercom-session ~/bin/intercom-machines \
       ~/bin/intercom-repos ~/bin/intercom-inbox-mutate ~/bin/intercom-inbox-listener
```

Each should show `-> /home/you/src/claude-config/bin/<name>` (or the Windows equivalent).

## Task Scheduler management (Windows)

The inbox listener runs as a persistent background process registered with Windows Task Scheduler. `install.sh` registers it automatically on Windows. Manual management:

```powershell
# Check status
schtasks /Query /TN intercom-inbox-listener

# Start manually (if not running after logon)
schtasks /Run /TN intercom-inbox-listener

# Stop
schtasks /End /TN intercom-inbox-listener

# Unregister
schtasks /Delete /TN intercom-inbox-listener /F

# Re-register (e.g. after changing the XML template)
schtasks /Create /XML "C:\Users\<you>\src\claude-config\windows\intercom-inbox-listener.xml.rendered" /TN intercom-inbox-listener /F
```

The task is triggered on logon and on wake-from-sleep. `MultipleInstancesPolicy: IgnoreNew` prevents duplicates if the trigger fires while the listener is already running.

To re-render the XML template (e.g. on a new machine or after changing the template):

```bash
cd ~/src/claude-config
sed "s|{{WINDOWS_USER}}|${USERNAME}|g" windows/intercom-inbox-listener.xml.template \
  > windows/intercom-inbox-listener.xml.rendered
# Then register in PowerShell:
schtasks /Create /XML "$(cygpath -w windows/intercom-inbox-listener.xml.rendered)" /TN intercom-inbox-listener /F
```

## UserPromptSubmit hook troubleshooting

The hook at `~/.claude/hooks/surface-intercom-replies.sh` (symlinked from `hooks/surface-intercom-replies.sh`) surfaces unread replies at the top of every Claude Code response.

**Hook not firing at all:**

```bash
# Check the hook is installed
ls -la ~/.claude/hooks/surface-intercom-replies.sh

# Check settings.json has the hook registered
jq '.hooks.UserPromptSubmit' ~/.claude/settings.json
```

If the hook entry is missing, re-run `./install.sh` to regenerate `~/.claude/settings.json`.

**Replies not appearing despite the listener running:**

```bash
# Check the inbox file exists and has content
ls -la ~/.local/state/intercom/inbox.jsonl
wc -l ~/.local/state/intercom/inbox.jsonl

# Check the cursor position
cat ~/.local/state/intercom/inbox.cursor

# Reset the cursor to re-read all replies (careful — will re-surface everything)
rm ~/.local/state/intercom/inbox.cursor
```

**Replies appear but then stop (cursor stuck):**

This indicates a torn/incomplete line at the end of inbox.jsonl — the listener was killed mid-write. The hook leaves the cursor at the last clean line and stops. Once the listener appends a complete line, the hook advances.

```bash
# Inspect the tail of the inbox
tail -5 ~/.local/state/intercom/inbox.jsonl | jq . 2>&1
# If the last line errors with parse failure, the line is torn — wait for the listener to finish
```

**Large replies going to files instead of inline:**

`intercom-inbox-mutate` auto-archives replies over 50 lines to `~/.intercom/responses/`. The hook surfaces a pointer line like `[full output (n lines) saved to ~/.intercom/responses/...]`. Open the file directly to read the content.

## MQTT password rotation

1. Update the password on the broker (broker-specific; typically edit the mosquitto password file and `mosquitto_passwd -U /path/to/passwords`).
2. Edit `~/.config/intercom/creds` on each dispatcher machine:
   ```bash
   # Edit MQTT_PASS= line
   nano ~/.config/intercom/creds
   ```
3. Restart the Task Scheduler listener on Windows so it picks up the new creds:
   ```powershell
   schtasks /End /TN intercom-inbox-listener
   schtasks /Run /TN intercom-inbox-listener
   ```
4. Test with `/machines` — should return a response within 2–3 seconds if the broker and receiver are up.

## Pointers

- **Runtime source**: [claude-intercom](https://github.com/danrichardson/claude-intercom) — the dispatcher helpers and receiver live here
- **Day-to-day usage**: [claude-intercom/docs/dogfooding-guide.md](https://github.com/danrichardson/claude-intercom/blob/main/docs/dogfooding-guide.md)
- **Slash commands**: `/register`, `/send`, `/draft`, `/machines`, `/repos` (all in `commands/`)
- **Session state**: `~/.config/intercom/session` (written by `intercom-session set`)
- **Inbox**: `~/.local/state/intercom/inbox.jsonl` (appended by `intercom-inbox-listener`)
- **Large reply archive**: `~/.intercom/responses/` (managed by `intercom-inbox-mutate`)
