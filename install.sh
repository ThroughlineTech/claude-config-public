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
link "$DOTFILES/CLAUDE.md"        "$HOME/.claude/CLAUDE.md"
link "$DOTFILES/commands"         "$HOME/.claude/commands"
link "$DOTFILES/plans"            "$HOME/.claude/plans"
link "$DOTFILES/brief-templates"  "$HOME/.claude/brief-templates"

#— Command aliases (from commands/aliases.map) ————————————————————
# Read aliases.map and create a symlink inside commands/ for each alias,
# pointing at the canonical command file. The alias files are gitignored,
# so they exist on each machine without polluting the repo.
echo ""
echo "Command aliases:"
ALIASES_MAP="$DOTFILES/commands/aliases.map"
if [ -f "$ALIASES_MAP" ]; then
  # First pass: remove any stale alias symlinks whose target no longer exists
  # or whose name no longer appears in aliases.map. Keeps the list in sync
  # when you remove/rename an alias.
  CURRENT_ALIASES=$(awk '!/^#/ && NF>=2 {print $1}' "$ALIASES_MAP" | tr '\n' ' ')
  for f in "$DOTFILES/commands/"*.md; do
    [ -L "$f" ] || continue
    base=$(basename "$f" .md)
    # Skip canonical ticket-* files (they're real files, not aliases).
    case "$base" in ticket-*) continue ;; esac
    # If this alias isn't in the current map, remove it.
    case " $CURRENT_ALIASES " in
      *" $base "*) ;;  # still in map, keep
      *) rm -f "$f"; echo "  - removed stale alias: $base.md" ;;
    esac
  done
  # Second pass: create/refresh symlinks for every alias in the map.
  while IFS= read -r line; do
    # Strip comments and blank lines.
    line="${line%%#*}"
    [ -z "${line// }" ] && continue
    alias=$(echo "$line" | awk '{print $1}')
    target=$(echo "$line" | awk '{print $2}')
    [ -z "$alias" ] || [ -z "$target" ] && continue
    TARGET_FILE="$DOTFILES/commands/$target.md"
    ALIAS_FILE="$DOTFILES/commands/$alias.md"
    if [ ! -f "$TARGET_FILE" ]; then
      echo "  ✗ alias $alias → $target: target missing ($TARGET_FILE)"
      continue
    fi
    # If the alias already exists and points at the right target, skip.
    if [ -L "$ALIAS_FILE" ] && [ "$(readlink "$ALIAS_FILE")" = "$target.md" ]; then
      echo "  ✓ /$alias → /$target"
      continue
    fi
    [ -e "$ALIAS_FILE" ] && rm "$ALIAS_FILE"
    # Use a relative target so the symlink works through any parent symlinks.
    ln -s "$target.md" "$ALIAS_FILE"
    echo "  → /$alias → /$target"
  done < "$ALIASES_MAP"
else
  echo "  - no aliases.map found; skipping"
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
  link "$DOTFILES/copilot-prompts/run-brief.prompt.md"            "$VSCODE_USER_DIR/prompts/run-brief.prompt.md"
  link "$DOTFILES/copilot-prompts/claude-global.instructions.md"  "$VSCODE_USER_DIR/prompts/claude-global.instructions.md"
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

#— Smoke tests ————————————————————————————————————————————————————
echo ""
echo "Smoke tests:"

ok() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; FAIL=1; }
FAIL=0

[ -L "$HOME/.claude/CLAUDE.md" ] && ok "CLAUDE.md symlinked" || fail "CLAUDE.md not symlinked"
[ -L "$HOME/.claude/commands" ] && ok "commands/ symlinked" || fail "commands/ not symlinked"
[ -L "$HOME/.claude/plans" ] && ok "plans/ symlinked" || fail "plans/ not symlinked"
[ -L "$HOME/.claude/brief-templates" ] && ok "brief-templates/ symlinked" || fail "brief-templates/ not symlinked"
[ -f "$HOME/.claude/commands/ticket-new.md" ] && ok "ticket-new.md visible via symlink" || fail "ticket-new.md not visible"
[ -f "$HOME/.claude/commands/ticket-delegate.md" ] && ok "ticket-delegate.md visible via symlink" || fail "ticket-delegate.md not visible"
[ -f "$HOME/.claude/brief-templates/implement.md" ] && ok "brief-templates/implement.md visible" || fail "brief template not visible"

if command -v jq >/dev/null 2>&1; then
  EFFORT=$(jq -r .effortLevel "$HOME/.claude/settings.json" 2>/dev/null || echo "")
  [ "$EFFORT" = "max" ] && ok "settings.json effortLevel=max" || fail "settings.json effortLevel != max (got: '$EFFORT')"
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
  1. Restart your shell, or:  source ~/.zshrc
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

EOF
