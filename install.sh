#!/usr/bin/env bash
set -euo pipefail

# On Git Bash for Windows: force real Windows symlinks instead of MSYS fake symlinks.
# Without this, `ln -s` creates regular files that pass MSYS checks but fail [ -L ]
# and aren't seen as symlinks by Windows-native apps (including VS Code and Claude Code).
# Requires Developer Mode enabled in Windows Settings (or running as admin).
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) export MSYS=winsymlinks:nativestrict ;;
esac

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d-%H%M%S)

#— Refuse to run from a git worktree ————————————————————————————————
# Every `link` call below captures $DOTFILES as the symlink target. If
# $DOTFILES is a worktree path, all symlinks in ~/.claude/ point into the
# worktree and break the moment the worktree is reaped after /ticket-ship.
# Detect and redirect the user to the main checkout. (CCONF-14)
if command -v git >/dev/null 2>&1; then
  GIT_DIR=$(git -C "$DOTFILES" rev-parse --path-format=absolute --git-dir 2>/dev/null || echo "")
  GIT_COMMON_DIR=$(git -C "$DOTFILES" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "")
  if [ -n "$GIT_DIR" ] && [ -n "$GIT_COMMON_DIR" ] && [ "$GIT_DIR" != "$GIT_COMMON_DIR" ]; then
    MAIN_REPO=$(dirname "$GIT_COMMON_DIR")
    echo "✗ Refusing to run install.sh from a git worktree."
    echo ""
    echo "  Worktree:   $DOTFILES"
    echo "  Main repo:  $MAIN_REPO"
    echo ""
    echo "  Symlinks in ~/.claude/ would point at this worktree and break"
    echo "  when the worktree is reaped after /ticket-ship. Run install.sh"
    echo "  from the main checkout instead:"
    echo ""
    echo "    bash \"$MAIN_REPO/install.sh\""
    exit 1
  fi
fi

mkdir -p "$HOME/.claude"

#— helper: idempotent symlink with backup —————————————————————————
link() {
  local src="$1" dst="$2"
  if [ -L "$dst" ]; then
    if [ "$(readlink "$dst")" = "$src" ]; then
      echo "  ✓ $dst already linked"
      return
    fi
    rm "$dst"
  elif [ -e "$dst" ]; then
    mv "$dst" "$dst.backup.$TS"
    echo "  ↪ backed up $dst → $dst.backup.$TS"
  fi
  ln -s "$src" "$dst"
  echo "  → $dst → $src"
}

echo "Installing claude-config from $DOTFILES"
echo ""
echo "Symlinks:"

#— Claude Code symlinks ———————————————————————————————————————————
link "$DOTFILES/CLAUDE.md"           "$HOME/.claude/CLAUDE.md"
link "$DOTFILES/plan-mode.md"        "$HOME/.claude/plan-mode.md"
link "$DOTFILES/brainstorm-mode.md"  "$HOME/.claude/brainstorm-mode.md"
link "$DOTFILES/commands"            "$HOME/.claude/commands"
link "$DOTFILES/plans"               "$HOME/.claude/plans"
link "$DOTFILES/brief-templates"     "$HOME/.claude/brief-templates"
link "$DOTFILES/agents"              "$HOME/.claude/agents"
link "$DOTFILES/operation-templates" "$HOME/.claude/operation-templates"

#— Generate alias wrapper files from commands/aliases.map ———————————
# Real .md files (not symlinks) so the Claude Code harness doesn't dedupe
# alias and canonical to a single entry. Each wrapper has its own frontmatter
# and delegates to the canonical command via $ARGUMENTS.
ALIAS_MAP="$DOTFILES/commands/aliases.map"
if [ -f "$ALIAS_MAP" ]; then
  echo ""
  echo "Alias wrappers (from commands/aliases.map):"

  # First, clean up any legacy alias symlinks left over from the old scheme.
  for f in "$DOTFILES/commands/"*.md; do
    [ -L "$f" ] || continue
    base=$(basename "$f" .md)
    case "$base" in ticket-*) continue ;; esac
    rm -f "$f"
    echo "  - removed legacy alias symlink: commands/$base.md"
  done

  while IFS= read -r line || [ -n "$line" ]; do
    # Strip comments and blank lines
    case "$line" in ''|\#*) continue ;; esac
    alias=$(echo "$line" | awk '{print $1}')
    target=$(echo "$line" | awk '{print $2}')
    [ -n "$alias" ] && [ -n "$target" ] || continue

    target_file="$DOTFILES/commands/$target.md"
    if [ ! -f "$target_file" ]; then
      echo "  ⚠ $alias → $target: target file missing, skipping"
      continue
    fi

    # Extract the canonical command's argument-hint (if any) so the alias
    # tooltip also shows the parameters.
    arg_hint=$(awk '
      /^---$/ { fm = !fm; next }
      fm && /^argument-hint:/ {
        sub(/^argument-hint:[[:space:]]*/, "")
        gsub(/^[\x27"]|[\x27"]$/, "")
        print
        exit
      }
    ' "$target_file")

    wrapper="$DOTFILES/commands/$alias.md"
    {
      echo "---"
      if [ -n "$arg_hint" ]; then
        echo "description: 'alias for /$target — $arg_hint'"
        echo "argument-hint: '$arg_hint'"
      else
        echo "description: 'alias for /$target'"
      fi
      echo "---"
      echo ""
      echo "This is a shortcut for \`/$target\`. Execute the \`/$target\` slash command now with the following arguments: \$ARGUMENTS"
    } > "$wrapper"
    echo "  → /$alias → /$target"
  done < "$ALIAS_MAP"

  # Ensure every generated alias wrapper is in .gitignore
  GITIGNORE="$DOTFILES/.gitignore"
  touch "$GITIGNORE"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|\#*) continue ;; esac
    alias=$(echo "$line" | awk '{print $1}')
    [ -n "$alias" ] || continue
    entry="commands/$alias.md"
    if ! grep -qxF "$entry" "$GITIGNORE"; then
      # Find the alias block marker or append at the end
      if grep -q "Generated by install.sh from commands/aliases.map" "$GITIGNORE"; then
        # Append after the last commands/*.md line in the alias block
        last_line=$(grep -n '^commands/.*\.md$' "$GITIGNORE" | tail -1 | cut -d: -f1)
        if [ -n "$last_line" ]; then
          sed -i "${last_line}a\\${entry}" "$GITIGNORE"
        else
          echo "$entry" >> "$GITIGNORE"
        fi
      else
        # No alias block yet — create one
        printf '\n# Generated by install.sh from commands/aliases.map — real files, not symlinks\n' >> "$GITIGNORE"
        printf '# (one line per alias defined in aliases.map)\n' >> "$GITIGNORE"
        echo "$entry" >> "$GITIGNORE"
      fi
      echo "  + added $entry to .gitignore"
    fi
  done < "$ALIAS_MAP"
fi

#— Settings merge (jq) ————————————————————————————————————————————
echo ""
echo "Settings merge:"

PLATFORM=""
case "$(uname -s)" in
  Darwin)               PLATFORM="mac" ;;
  Linux)                PLATFORM="mac" ;;  # close enough for tool allows
  MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
esac
PLATFORM_FILE="$DOTFILES/settings.$PLATFORM.json"
[ -f "$PLATFORM_FILE" ] || PLATFORM_FILE="$DOTFILES/settings.mac.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "  ⚠ jq not installed; skipping settings merge."
  echo "    Install with: brew install jq   (or apt install jq)"
else
  if [ -f "$HOME/.claude/settings.json" ] && [ ! -L "$HOME/.claude/settings.json" ]; then
    cp "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.backup.$TS"
    echo "  ↪ backed up existing settings.json → settings.json.backup.$TS"
  fi
  jq -s '
    .[0] as $base | .[1] as $plat |
    ($base * $plat)
    | .permissions.allow = (($base.permissions.allow // []) + ($plat.permissions.allow // []))
    | .permissions.deny  = (($base.permissions.deny  // []) + ($plat.permissions.deny  // []))
  ' "$DOTFILES/settings.base.json" "$PLATFORM_FILE" > "$HOME/.claude/settings.json"
  echo "  → wrote merged ~/.claude/settings.json (base + $PLATFORM)"
fi

#— Generate Copilot global instructions file from CLAUDE.md ——————————
echo ""
echo "Generating Copilot instructions file from CLAUDE.md:"
{
  echo "---"
  echo 'applyTo: "**"'
  echo "---"
  echo ""
  cat "$DOTFILES/CLAUDE.md"
} > "$DOTFILES/copilot-prompts/claude-global.instructions.md"
echo "  → wrote copilot-prompts/claude-global.instructions.md"

#— Generate Copilot plan-mode instructions file from plan-mode.md ————
{
  echo "---"
  echo 'applyTo: "**"'
  echo "---"
  echo ""
  cat "$DOTFILES/plan-mode.md"
} > "$DOTFILES/copilot-prompts/plan-mode.instructions.md"
echo "  → wrote copilot-prompts/plan-mode.instructions.md"

#— Generate Copilot brainstorm-mode instructions from brainstorm-mode.md —
{
  echo "---"
  echo 'applyTo: "**"'
  echo "---"
  echo ""
  cat "$DOTFILES/brainstorm-mode.md"
} > "$DOTFILES/copilot-prompts/brainstorm-mode.instructions.md"
echo "  → wrote copilot-prompts/brainstorm-mode.instructions.md"

#— Regenerate Copilot prompt mirrors from commands/*.md ——————————————
# Each canonical Claude command (commands/ticket-*.md, commands/plan-*.md)
# has a Copilot mirror in copilot-prompts/. bin/sync-copilot-prompts is
# the deterministic port: it extracts frontmatter, copies the body, and
# emits per-command Copilot-specific overrides for ticket-chain,
# ticket-batch, and ticket-investigate.
if [ -f "$DOTFILES/bin/sync-copilot-prompts" ]; then
  echo ""
  echo "Copilot prompt mirrors:"
  bash "$DOTFILES/bin/sync-copilot-prompts" | sed 's/^/  /'
else
  echo ""
  echo "Copilot prompt mirrors:"
  echo "  ⚠ $DOTFILES/bin/sync-copilot-prompts not found; skipping"
fi

#— VS Code Copilot prompts + instructions ————————————————————————————
echo ""
echo "VS Code Copilot wiring:"

VSCODE_USER_DIR=""
case "$(uname -s)" in
  Darwin) VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User" ;;
  Linux)  VSCODE_USER_DIR="$HOME/.config/Code/User" ;;
  MINGW*|MSYS*|CYGWIN*) VSCODE_USER_DIR="$APPDATA/Code/User" ;;
esac

if [ -n "$VSCODE_USER_DIR" ] && [ -d "$VSCODE_USER_DIR" ]; then
  mkdir -p "$VSCODE_USER_DIR/prompts"
  for f in "$DOTFILES/copilot-prompts/"*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    link "$f" "$VSCODE_USER_DIR/prompts/$name"
  done
else
  echo "  - VS Code not detected at $VSCODE_USER_DIR; skipping"
fi

#— PATH for claude-handoff ————————————————————————————————————————
echo ""
echo "PATH:"

# Pick the right shell rc: prefer .zshrc on Mac, .bashrc on Git Bash/Linux,
# but if both exist or neither, fall back sensibly.
SHELL_RC=""
if [ -n "${ZSH_VERSION:-}" ] && [ -f "$HOME/.zshrc" ]; then
  SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.zshrc" ] && [ ! -f "$HOME/.bashrc" ]; then
  SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
  SHELL_RC="$HOME/.bashrc"
elif [ -f "$HOME/.zshrc" ]; then
  SHELL_RC="$HOME/.zshrc"
fi

SHELL_SOURCE_HINT="source ~/.zshrc"
if [ -n "$SHELL_RC" ]; then
  case "$(basename "$SHELL_RC")" in
    .bashrc) SHELL_SOURCE_HINT="source ~/.bashrc" ;;
    .zshrc) SHELL_SOURCE_HINT="source ~/.zshrc" ;;
    *) SHELL_SOURCE_HINT="source $SHELL_RC" ;;
  esac
fi

if [ -n "$SHELL_RC" ]; then
  if grep -qF "$DOTFILES/bin" "$SHELL_RC" 2>/dev/null; then
    echo "  ✓ $DOTFILES/bin already in $(basename "$SHELL_RC")"
  else
    {
      echo ""
      echo "# claude-config"
      echo "export PATH=\"$DOTFILES/bin:\$PATH\""
    } >> "$SHELL_RC"
    echo "  → added $DOTFILES/bin to PATH in $(basename "$SHELL_RC")"
  fi
else
  echo "  - no ~/.zshrc or ~/.bashrc found; add this to your shell rc manually:"
  echo "      export PATH=\"$DOTFILES/bin:\$PATH\""
fi

chmod +x "$DOTFILES/bin/"* 2>/dev/null || true

#— Intercom subsystem (MQTT era) ——————————————————————————————————————
#
# Symlinks dispatcher helpers from bin/ into ~/bin/ and installs the
# UserPromptSubmit hook. No clone, no bun, no MCP — helpers call
# mosquitto_pub/sub directly and source ~/.config/intercom/creds at runtime.
#
INTERCOM_RAN=0

echo ""
echo "Intercom:"

# 5a. Mirror bin/* into ~/bin/ and hook into ~/.claude/hooks/
mkdir -p "$HOME/bin"
for f in "$DOTFILES/bin/"*; do
  name=$(basename "$f")
  link "$f" "$HOME/bin/$name"
done

mkdir -p "$HOME/.claude/hooks"
link "$DOTFILES/hooks/surface-intercom-replies.sh" "$HOME/.claude/hooks/surface-intercom-replies.sh"

# 5b. Gate on mosquitto_pub availability
if ! command -v mosquitto_pub >/dev/null 2>&1; then
  echo "  ⚠ mosquitto_pub not found — intercom helpers are symlinked but won't work until mosquitto is installed."
  echo "    Mac:     brew install mosquitto"
  echo "    Windows: winget install cedalo.mosquitto"
  echo "    Linux:   sudo apt install mosquitto-clients"
else
  echo "  ✓ mosquitto_pub available"
fi

# 5c. Creds file prompt (skip if non-interactive or file already exists)
CREDS_FILE="$HOME/.config/intercom/creds"
if [ ! -f "$CREDS_FILE" ]; then
  if [ -t 0 ]; then
    echo "  No $CREDS_FILE found. Enter MQTT broker credentials (Ctrl+C to skip):"
    read -r -p "    MQTT_HOST: " MQTT_HOST_VAL
    read -r -p "    MQTT_PORT [1883]: " MQTT_PORT_VAL
    MQTT_PORT_VAL="${MQTT_PORT_VAL:-1883}"
    read -r -p "    MQTT_USER: " MQTT_USER_VAL
    read -r -s -p "    MQTT_PASS: " MQTT_PASS_VAL
    echo ""
    if [ -n "$MQTT_HOST_VAL" ]; then
      mkdir -p "$(dirname "$CREDS_FILE")"
      {
        echo "MQTT_HOST=$MQTT_HOST_VAL"
        echo "MQTT_PORT=$MQTT_PORT_VAL"
        echo "MQTT_USER=$MQTT_USER_VAL"
        echo "MQTT_PASS=$MQTT_PASS_VAL"
      } > "$CREDS_FILE"
      chmod 600 "$CREDS_FILE"
      echo "  → wrote $CREDS_FILE (chmod 600)"
    else
      echo "  - skipped creds (no host entered); create $CREDS_FILE manually"
    fi
  else
    echo "  - non-interactive: skipping creds prompt; create $CREDS_FILE manually"
  fi
else
  echo "  ✓ $CREDS_FILE already exists"
fi

# 5d. Windows only: render Task Scheduler XML and register the listener task
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    XML_TEMPLATE="$DOTFILES/windows/intercom-inbox-listener.xml.template"
    XML_RENDERED="$DOTFILES/windows/intercom-inbox-listener.xml.rendered"
    if [ -f "$XML_TEMPLATE" ]; then
      sed "s|{{WINDOWS_USER}}|${USERNAME:-}|g" "$XML_TEMPLATE" > "$XML_RENDERED"
      echo "  → rendered $XML_RENDERED"
      if command -v schtasks >/dev/null 2>&1; then
        # Convert POSIX path to Windows path for schtasks
        XML_WIN=$(cygpath -w "$XML_RENDERED" 2>/dev/null || echo "$XML_RENDERED")
        # MSYS_NO_PATHCONV=1 stops Git Bash from mangling the /Create /XML /TN /F
        # flags into "C:/Program Files/Git/Create" etc.
        MSYS_NO_PATHCONV=1 schtasks /Create /XML "$XML_WIN" /TN intercom-inbox-listener /F \
          && echo "  ✓ Task Scheduler: intercom-inbox-listener registered" \
          || echo "  ⚠ schtasks failed — register manually: schtasks /Create /XML \"$XML_WIN\" /TN intercom-inbox-listener /F"
      else
        echo "  ⚠ schtasks not found — register task manually using $XML_WIN"
      fi
    else
      echo "  ⚠ $XML_TEMPLATE not found; skipping Task Scheduler setup"
    fi
    ;;
esac

# 5f. Surgical .mcp.json cleanup: remove intercom MCP server if present
#     (left over from TKT-001 HTTP-era install — no-op if file absent or key missing)
MCP_JSON="$HOME/.claude/.mcp.json"
if [ -f "$MCP_JSON" ] && command -v jq >/dev/null 2>&1; then
  if jq -e '.mcpServers.intercom' "$MCP_JSON" >/dev/null 2>&1; then
    jq 'del(.mcpServers.intercom)' "$MCP_JSON" > "$MCP_JSON.tmp"
    mv "$MCP_JSON.tmp" "$MCP_JSON"
    echo "  → removed stale mcpServers.intercom entry from $MCP_JSON"
  fi
fi

INTERCOM_RAN=1

#— Plane MCP (Claude user scope + Copilot user scope) ————————————————
#
# Reads PLANE_BASE_URL, PLANE_API_KEY, PLANE_WORKSPACE_SLUG from secrets/.env
# (gitignored) and registers a `plane` stdio MCP server in two places:
#   - Claude Code user scope  → ~/.claude.json     (every session, every dir)
#   - Copilot / VS Code       → $VSCODE_USER_DIR/mcp.json
# Both read the same key. Rotating the token means editing secrets/.env and re-running install.
#
echo ""
echo "Plane MCP:"

PLANE_OK=0
SECRETS_ENV="$DOTFILES/secrets/.env"
if [ ! -f "$SECRETS_ENV" ]; then
  echo "  - $SECRETS_ENV not found; skipping (add PLANE_BASE_URL, PLANE_API_KEY, PLANE_WORKSPACE_SLUG to enable)"
elif ! command -v jq >/dev/null 2>&1; then
  echo "  ⚠ jq not installed; skipping Plane MCP setup"
else
  get_secret() {
    grep -m1 "^$1=" "$SECRETS_ENV" 2>/dev/null | sed -e "s/^$1=//" -e "s/^['\"]//" -e "s/['\"]$//"
  }
  PLANE_BASE_URL=$(get_secret PLANE_BASE_URL)
  PLANE_API_KEY=$(get_secret PLANE_API_KEY)
  PLANE_WORKSPACE_SLUG=$(get_secret PLANE_WORKSPACE_SLUG)

  if [ -z "$PLANE_BASE_URL" ] || [ -z "$PLANE_API_KEY" ] || [ -z "$PLANE_WORKSPACE_SLUG" ]; then
    echo "  - secrets/.env missing one or more of PLANE_BASE_URL / PLANE_API_KEY / PLANE_WORKSPACE_SLUG; skipping"
  elif ! UVX_PATH="$(command -v uvx)" || [ -z "$UVX_PATH" ]; then
    echo "  ⚠ uvx not on PATH; skipping (install uv: https://docs.astral.sh/uv/)"
  else
    # Store a host-agnostic executable name in user config so stale cross-OS
    # config copies don't pin to an absolute path from another platform.
    UVX_CMD="uvx"

    # 1. Claude Code user scope — merge into ~/.claude.json .mcpServers.plane
    CLAUDE_JSON="$HOME/.claude.json"
    if [ -f "$CLAUDE_JSON" ]; then
      jq --arg cmd "$UVX_CMD" --arg base "$PLANE_BASE_URL" --arg key "$PLANE_API_KEY" --arg slug "$PLANE_WORKSPACE_SLUG" '
        .mcpServers.plane = {
          type: "stdio",
          command: $cmd,
          args: ["plane-mcp-server", "stdio"],
          env: {PLANE_BASE_URL: $base, PLANE_API_KEY: $key, PLANE_WORKSPACE_SLUG: $slug}
        }
      ' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
      echo "  → registered plane in ~/.claude.json (user scope)"
      PLANE_OK=1
    else
      echo "  - $CLAUDE_JSON not found; run 'claude' once to create it, then re-run install"
    fi

    # 2. Copilot / VS Code user scope — merge into $VSCODE_USER_DIR/mcp.json (top key: "servers")
    #    Use the stdio proxy to filter 109 → 17 tools so Copilot's token budget isn't exceeded.
    if [ -n "$VSCODE_USER_DIR" ] && [ -d "$VSCODE_USER_DIR" ]; then
      COPILOT_MCP="$VSCODE_USER_DIR/mcp.json"
      PROXY_POSIX="$DOTFILES/bin/plane-mcp-proxy.py"
      # VS Code on Windows needs a Windows-style path; cygpath -m gives C:/... form.
      case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) PROXY_PATH="$(cygpath -m "$PROXY_POSIX")" ;;
        *) PROXY_PATH="$PROXY_POSIX" ;;
      esac
      if [ -f "$COPILOT_MCP" ]; then
        jq --arg proxy "$PROXY_PATH" --arg base "$PLANE_BASE_URL" --arg key "$PLANE_API_KEY" --arg slug "$PLANE_WORKSPACE_SLUG" '
          .servers.plane = {
            command: "uv",
            args: ["run", "--no-project", $proxy],
            env: {PLANE_BASE_URL: $base, PLANE_API_KEY: $key, PLANE_WORKSPACE_SLUG: $slug}
          }
        ' "$COPILOT_MCP" > "$COPILOT_MCP.tmp" && mv "$COPILOT_MCP.tmp" "$COPILOT_MCP"
        echo "  → updated $COPILOT_MCP (proxy: $PROXY_PATH)"
      else
        jq -n --arg proxy "$PROXY_PATH" --arg base "$PLANE_BASE_URL" --arg key "$PLANE_API_KEY" --arg slug "$PLANE_WORKSPACE_SLUG" '
          {servers: {plane: {
            command: "uv",
            args: ["run", "--no-project", $proxy],
            env: {PLANE_BASE_URL: $base, PLANE_API_KEY: $key, PLANE_WORKSPACE_SLUG: $slug}
          }}}
        ' > "$COPILOT_MCP"
        echo "  → wrote $COPILOT_MCP (proxy: $PROXY_PATH)"
      fi
    else
      echo "  - VS Code user dir not detected; skipped Copilot mcp.json"
    fi

    # 3. ~/.claude/plane-config.md — credentials for TravelAgent VS Code extension
    GLOBAL_PLANE_MD="$HOME/.claude/plane-config.md"
    printf '# Plane Agent Config\n# Generated by install.sh.\n\n- API URL: %s\n- API key: %s\n- Workspace slug: %s\n' \
      "$PLANE_BASE_URL" "$PLANE_API_KEY" "$PLANE_WORKSPACE_SLUG" > "$GLOBAL_PLANE_MD"
    echo "  → wrote $GLOBAL_PLANE_MD"
  fi
fi

#— Extension compile (optional) ——————————————————————————————————————
#
# extension/ holds the TravelAgent VS Code extension source.
# Run `npm install` manually the first time; thereafter install.sh will
# recompile automatically whenever node_modules/ is present.
#
echo ""
echo "Extension (TravelAgent):"
EXT_DIR="$DOTFILES/extension"
if [ -d "$EXT_DIR/node_modules" ]; then
  if command -v npm >/dev/null 2>&1; then
    (cd "$EXT_DIR" && npm run compile 2>&1 | sed 's/^/  /') \
      && echo "  ✓ extension compiled" \
      || echo "  ✗ extension compile failed — run: cd extension && npm run compile"
  else
    echo "  ⚠ npm not found; skipping extension compile"
  fi
else
  echo "  - extension/node_modules/ not found; run: cd extension && npm install && npm run compile"
fi

#— Smoke tests ————————————————————————————————————————————————————
echo ""
echo "Smoke tests:"

ok() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; FAIL=1; }
warn() { echo "  ⚠ $1"; }
FAIL="${FAIL:-0}"

[ -L "$HOME/.claude/CLAUDE.md" ] && ok "CLAUDE.md symlinked" || fail "CLAUDE.md not symlinked"
[ -L "$HOME/.claude/plan-mode.md" ] && ok "plan-mode.md symlinked" || fail "plan-mode.md not symlinked"
[ -L "$HOME/.claude/brainstorm-mode.md" ] && ok "brainstorm-mode.md symlinked" || fail "brainstorm-mode.md not symlinked"
[ -L "$HOME/.claude/commands" ] && ok "commands/ symlinked" || fail "commands/ not symlinked"
[ -L "$HOME/.claude/plans" ] && ok "plans/ symlinked" || fail "plans/ not symlinked"
[ -L "$HOME/.claude/brief-templates" ] && ok "brief-templates/ symlinked" || fail "brief-templates/ not symlinked"
[ -L "$HOME/.claude/agents" ] && ok "agents/ symlinked" || fail "agents/ not symlinked"
[ -L "$HOME/.claude/operation-templates" ] && ok "operation-templates/ symlinked" || fail "operation-templates/ not symlinked"
[ -f "$HOME/.claude/commands/ticket-new.md" ] && ok "ticket-new.md visible via symlink" || fail "ticket-new.md not visible"
[ -f "$HOME/.claude/commands/ticket-delegate.md" ] && ok "ticket-delegate.md visible via symlink" || fail "ticket-delegate.md not visible"
[ -f "$HOME/.claude/commands/op-scaffold.md" ] && ok "op-scaffold.md visible via symlink" || fail "op-scaffold.md not visible"
[ -f "$HOME/.claude/commands/op-run.md" ] && ok "op-run.md visible via symlink" || fail "op-run.md not visible"
[ -f "$HOME/.claude/agents/operation-conductor.md" ] && ok "operation-conductor.md visible via symlink" || fail "operation-conductor.md not visible"
[ -f "$HOME/.claude/agents/operation-task-lead.md" ] && ok "operation-task-lead.md visible via symlink" || fail "operation-task-lead.md not visible"
[ -f "$HOME/.claude/agents/operation-worker.md" ] && ok "operation-worker.md visible via symlink" || fail "operation-worker.md not visible"
[ -f "$HOME/.claude/operation-templates/META_PROMPT_FOR_PLAN_OPUS.md" ] && ok "META_PROMPT_FOR_PLAN_OPUS.md visible via symlink" || fail "META_PROMPT_FOR_PLAN_OPUS.md not visible"
[ -f "$HOME/.claude/brief-templates/implement.md" ] && ok "brief-templates/implement.md visible" || fail "brief template not visible"

# Dual-world dispatch (Plan 2 Phase 8): every ported workflow command must
# contain a "Pre-flight: detect backend" section. Presence of that section
# is how each command decides between the Plane and Markdown paths at run
# time. If any command is missing it, dispatch silently defaults and we
# lose the backend gate — so fail loudly here.
DISPATCH_OK=1
for cmd in "$DOTFILES/commands/"ticket-*.md "$DOTFILES/commands/"plan-*.md; do
  [ -f "$cmd" ] || continue
  name=$(basename "$cmd")
  # ticket-install.md is the bootstrapper — it *creates* the backend choice
  # rather than dispatching on it, so it's exempt.
  [ "$name" = "ticket-install.md" ] && continue
  if ! grep -qF "Pre-flight: detect backend" "$cmd"; then
    fail "$name missing 'Pre-flight: detect backend' section (dual-world dispatch broken)"
    DISPATCH_OK=0
  fi
done
[ "$DISPATCH_OK" = "1" ] && ok "dual-world dispatch present in all ported commands"

if command -v jq >/dev/null 2>&1; then
  EFFORT=$(jq -r .effortLevel "$HOME/.claude/settings.json" 2>/dev/null || echo "")
  [ "$EFFORT" = "max" ] && ok "settings.json effortLevel=max" || fail "settings.json effortLevel != max (got: '$EFFORT')"
fi

if [ "$INTERCOM_RAN" = "1" ]; then
  [ -L "$HOME/bin/send-job" ] && ok "~/bin/send-job symlinked" || fail "~/bin/send-job not symlinked"
  [ -L "$HOME/.claude/hooks/surface-intercom-replies.sh" ] && ok "hook symlinked" || fail "hook not symlinked at ~/.claude/hooks/"
  [ -f "$HOME/.config/intercom/creds" ] \
    && ok "~/.config/intercom/creds present" \
    || warn "~/.config/intercom/creds missing — intercom helpers will fail until you create it"
fi

if [ "$PLANE_OK" = "1" ] && command -v jq >/dev/null 2>&1; then
  CLAUDE_PLANE_CMD=$(jq -r '.mcpServers.plane.command // empty' "$HOME/.claude.json" 2>/dev/null || echo "")
  [ -n "$CLAUDE_PLANE_CMD" ] \
    && ok "plane MCP registered in ~/.claude.json" \
    || fail "plane MCP not found in ~/.claude.json after install"

  if [ -n "$CLAUDE_PLANE_CMD" ]; then
    case "$(uname -s)" in
      Darwin|Linux)
        if printf '%s' "$CLAUDE_PLANE_CMD" | grep -Eq '^[A-Za-z]:\\'; then
          fail "~/.claude.json plane command looks Windows-specific on this host: $CLAUDE_PLANE_CMD"
        else
          ok "~/.claude.json plane command is host-compatible"
        fi
        ;;
      MINGW*|MSYS*|CYGWIN*)
        if [[ "$CLAUDE_PLANE_CMD" == /* ]]; then
          fail "~/.claude.json plane command looks POSIX-specific on Windows host: $CLAUDE_PLANE_CMD"
        else
          ok "~/.claude.json plane command is host-compatible"
        fi
        ;;
    esac
  fi

  [ -f "$DOTFILES/bin/plane-mcp-proxy.py" ] \
    && ok "plane-mcp-proxy.py present" \
    || fail "plane-mcp-proxy.py missing (bin/plane-mcp-proxy.py not found)"

  if [ -n "$VSCODE_USER_DIR" ] && [ -f "$VSCODE_USER_DIR/mcp.json" ]; then
    COPILOT_PLANE_CMD=$(jq -r '.servers.plane.command // empty' "$VSCODE_USER_DIR/mcp.json" 2>/dev/null || echo "")
    [ -n "$COPILOT_PLANE_CMD" ] \
      && ok "plane MCP registered in Copilot mcp.json" \
      || fail "plane MCP not found in Copilot mcp.json after install"

    if [ -n "$COPILOT_PLANE_CMD" ]; then
      # Verify the Copilot mcp.json uses the proxy (command should be "uv", not "uvx")
      [ "$COPILOT_PLANE_CMD" = "uv" ] \
        && ok "Copilot mcp.json uses plane-mcp-proxy (command=uv)" \
        || fail "Copilot mcp.json not using proxy (command=$COPILOT_PLANE_CMD, expected uv)"

      case "$(uname -s)" in
        Darwin|Linux)
          if printf '%s' "$COPILOT_PLANE_CMD" | grep -Eq '^[A-Za-z]:\\'; then
            fail "Copilot mcp.json plane command looks Windows-specific on this host: $COPILOT_PLANE_CMD"
          else
            ok "Copilot mcp.json plane command is host-compatible"
          fi
          ;;
        MINGW*|MSYS*|CYGWIN*)
          if [[ "$COPILOT_PLANE_CMD" == /* ]]; then
            fail "Copilot mcp.json plane command looks POSIX-specific on Windows host: $COPILOT_PLANE_CMD"
          else
            ok "Copilot mcp.json plane command is host-compatible"
          fi
          ;;
      esac
    fi
  fi
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "✓ Install complete."
else
  echo "✗ Install completed with errors above."
  exit 1
fi

#— Next steps ————————————————————————————————————————————————————
cat <<EOF

Next steps:
  1. Restart your shell, or:  $SHELL_SOURCE_HINT
     (so 'claude-handoff' is on PATH)

  2. To push this repo to GitHub (run when ready):
       cd $DOTFILES
       gh repo create claude-config --private --source=. --remote=origin --description="Claude Code dotfiles + universal ticket workflow"
       git push -u origin main

  3. VS Code Copilot Chat now picks up CLAUDE.md automatically via the
     instructions file at User/prompts/claude-global.instructions.md.
     No settings.json paste needed. Test in a new Copilot Chat with:
       "send me a test prowl"
     If a notification arrives, the wiring is correct.

  4. Per-project backend (dual-world dispatch):
       /ticket-* commands auto-detect each project's backend at run time.
         - .claude/plane-config.md present  → Plane backend
         - .claude/ticket-config.md + tickets/ → Markdown backend
         - neither                            → run /ticket-install
       Both backends are installed globally; per-project config decides
       which one each command actually uses. Until Plan 3 finishes, you
       can have Plane and Markdown projects side-by-side on one machine.

EOF
