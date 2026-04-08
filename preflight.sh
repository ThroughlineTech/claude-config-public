#!/usr/bin/env bash
# preflight.sh — read-only check that install.sh will succeed on this machine.
# Mutates nothing. Run this BEFORE install.sh on any new machine.

# On Git Bash for Windows: force real Windows symlinks (matches install.sh).
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) export MSYS=winsymlinks:nativestrict ;;
esac

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0
WARN=0

ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠ $1"; WARN=$((WARN+1)); }
info() { echo "    $1"; }

echo "claude-config preflight"
echo "Repo: $DOTFILES"
echo ""

#— 1. Platform detection ——————————————————————————————————————————————
echo "[1] Platform"
UNAME="$(uname -s)"
case "$UNAME" in
  Darwin)               PLATFORM="mac"     ; ok "macOS detected ($UNAME)" ;;
  Linux)                PLATFORM="linux"   ; ok "Linux detected ($UNAME)" ;;
  MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ; ok "Windows shell detected ($UNAME)"
                                              info "(Git Bash / MSYS / Cygwin — install.sh will pick settings.windows.json)" ;;
  *)                    PLATFORM="unknown" ; bad "Unknown platform ($UNAME) — install.sh may pick wrong settings file" ;;
esac
echo ""

#— 2. Required tools ——————————————————————————————————————————————————
echo "[2] Required tools"
for tool in git jq ln readlink chmod mkdir grep; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool present ($(command -v "$tool"))"
  else
    bad "$tool MISSING — install before running install.sh"
    case "$tool" in
      jq) info "Mac:     brew install jq"
          info "Linux:   sudo apt install jq"
          info "Windows: winget install jqlang.jq" ;;
    esac
  fi
done
echo ""

#— 3. Symlink capability ——————————————————————————————————————————————
echo "[3] Symlink capability"
TMPDIR_TEST="${TMPDIR:-/tmp}"
TMPLINK="$TMPDIR_TEST/claude-config-preflight-link-$$"
TMPTARGET="$TMPDIR_TEST/claude-config-preflight-target-$$"
echo "preflight test" > "$TMPTARGET"
if ln -s "$TMPTARGET" "$TMPLINK" 2>/dev/null; then
  if [ -L "$TMPLINK" ]; then
    LINK_TARGET="$(readlink "$TMPLINK" 2>/dev/null || echo "")"
    if [ "$LINK_TARGET" = "$TMPTARGET" ]; then
      ok "ln -s creates real symlinks"
    else
      bad "ln -s ran but readlink returned wrong target — symlinks may be broken"
    fi
  else
    bad "ln -s ran but the result is not a symlink (Git Bash 'fake symlink' mode?)"
    info "On Git Bash, this means MSYS is creating fake symlinks instead of real ones."
    info "Fix: in this shell, run:"
    info "    export MSYS=winsymlinks:nativestrict"
    info "Then re-run preflight. To persist:"
    info "    echo 'export MSYS=winsymlinks:nativestrict' >> ~/.bashrc"
    info "(Also requires Developer Mode ON in Windows Settings, which you likely already have.)"
  fi
  rm -f "$TMPLINK"
else
  bad "ln -s failed — cannot create symlinks in $TMPDIR_TEST"
  if [ "$PLATFORM" = "windows" ]; then
    info "Enable Windows Developer Mode (Settings → System → For developers → Developer Mode: On)"
    info "OR run Git Bash as Administrator for the install.sh invocation"
  fi
fi
rm -f "$TMPTARGET"
echo ""

#— 4. Repo files all present ——————————————————————————————————————————
echo "[4] Repo contents"
REPO_OK=1
for f in CLAUDE.md install.sh settings.base.json settings.mac.json settings.windows.json \
         commands/ticket-new.md commands/ticket-delegate.md commands/ticket-collect.md \
         commands/ticket-status.md commands/ticket-install.md \
         brief-templates/investigate.md brief-templates/implement.md brief-templates/review.md \
         brief-templates/verify-investigate.md brief-templates/verify-implement.md brief-templates/verify-review.md \
         copilot-prompts/run-brief.prompt.md \
         bin/claude-handoff; do
  if [ -e "$DOTFILES/$f" ]; then
    :
  else
    bad "missing: $f"
    REPO_OK=0
  fi
done
[ $REPO_OK -eq 1 ] && ok "all 18 expected files present"
echo ""

#— 5. ~/.claude state — what would get backed up ——————————————————————
echo "[5] What install.sh would back up (~/.claude/)"
mkdir -p "$HOME/.claude" 2>/dev/null
WOULD_BACKUP=0
for target in CLAUDE.md commands plans brief-templates settings.json; do
  path="$HOME/.claude/$target"
  if [ -L "$path" ]; then
    link_target="$(readlink "$path" 2>/dev/null || echo "")"
    if [ "$link_target" = "$DOTFILES/$target" ] || [ "$link_target" = "$DOTFILES/copilot-prompts/$target" ]; then
      ok "$target — already linked into this repo (no-op)"
    else
      warn "$target — already a symlink, but to '$link_target' (will be replaced by install.sh)"
      WOULD_BACKUP=$((WOULD_BACKUP+1))
    fi
  elif [ -e "$path" ]; then
    if [ -d "$path" ]; then
      count=$(find "$path" -type f 2>/dev/null | wc -l | tr -d ' ')
      warn "$target — directory exists with $count files (will be moved to ${target}.backup.{ts})"
    else
      size=$(wc -c < "$path" 2>/dev/null | tr -d ' ')
      warn "$target — file exists ($size bytes) (will be moved to ${target}.backup.{ts})"
    fi
    WOULD_BACKUP=$((WOULD_BACKUP+1))
  else
    ok "$target — does not exist (clean install)"
  fi
done
[ $WOULD_BACKUP -gt 0 ] && info "$WOULD_BACKUP item(s) will be backed up with timestamp suffix; nothing is deleted"
echo ""

#— 6. Settings.json contents (if any) ——————————————————————————————————
echo "[6] Existing settings.json analysis"
SJ="$HOME/.claude/settings.json"
if [ -f "$SJ" ] && command -v jq >/dev/null 2>&1; then
  ALLOWS=$(jq '.permissions.allow | length' "$SJ" 2>/dev/null || echo 0)
  DENIES=$(jq '.permissions.deny | length' "$SJ" 2>/dev/null || echo 0)
  ADDDIRS=$(jq '.permissions.additionalDirectories | length' "$SJ" 2>/dev/null || echo 0)
  EFFORT=$(jq -r '.effortLevel // "unset"' "$SJ" 2>/dev/null || echo unset)
  EXPMODE=$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS // "unset"' "$SJ" 2>/dev/null || echo unset)
  info "permissions.allow:                $ALLOWS entries"
  info "permissions.deny:                 $DENIES entries"
  info "permissions.additionalDirectories: $ADDDIRS entries"
  info "effortLevel:                       $EFFORT"
  info "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: $EXPMODE"
  if [ "$ALLOWS" -gt 0 ]; then
    warn "$ALLOWS accumulated allow grant(s) will NOT survive install.sh"
    info "install.sh regenerates settings.json from base + platform files."
    info "Backup is at settings.json.backup.{ts} — review post-install if you miss something."
    info "To preserve specific allows, add them to settings.${PLATFORM}.json BEFORE installing."
  fi
  if [ "$ADDDIRS" -gt 0 ]; then
    warn "$ADDDIRS additionalDirectories entries will be DROPPED (these are machine-specific paths)"
    info "If any are still needed, re-add them to settings.${PLATFORM}.json after install."
  fi
else
  ok "no existing settings.json (or jq missing) — clean install"
fi
echo ""

#— 7. VS Code detection ———————————————————————————————————————————————
echo "[7] VS Code (Copilot) detection"
case "$PLATFORM" in
  mac)     VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User" ;;
  linux)   VSCODE_USER_DIR="$HOME/.config/Code/User" ;;
  windows) VSCODE_USER_DIR="$APPDATA/Code/User" ;;
  *)       VSCODE_USER_DIR="" ;;
esac
if [ -n "$VSCODE_USER_DIR" ] && [ -d "$VSCODE_USER_DIR" ]; then
  ok "VS Code user dir present ($VSCODE_USER_DIR)"
  if [ -d "$VSCODE_USER_DIR/prompts" ]; then
    EXISTING_PROMPTS=$(ls "$VSCODE_USER_DIR/prompts/" 2>/dev/null | wc -l | tr -d ' ')
    ok "prompts/ subdirectory present ($EXISTING_PROMPTS file(s))"
    for f in run-brief.prompt.md claude-global.instructions.md; do
      if [ -e "$VSCODE_USER_DIR/prompts/$f" ]; then
        if [ -L "$VSCODE_USER_DIR/prompts/$f" ]; then
          link_target=$(readlink "$VSCODE_USER_DIR/prompts/$f" 2>/dev/null || echo "")
          info "$f — already symlinked → $link_target"
        else
          warn "$f — exists as a file (not symlink); install.sh will back it up and replace"
        fi
      fi
    done
  else
    info "prompts/ subdirectory will be created"
  fi
  # Settings.json check for the deprecated copilot setting
  VSCODE_SETTINGS="$VSCODE_USER_DIR/settings.json"
  if [ -f "$VSCODE_SETTINGS" ] && command -v jq >/dev/null 2>&1; then
    HAS_DEPRECATED=$(jq -r '.["github.copilot.chat.codeGeneration.instructions"] // empty | length' "$VSCODE_SETTINGS" 2>/dev/null || echo 0)
    if [ -n "$HAS_DEPRECATED" ] && [ "$HAS_DEPRECATED" != "0" ] && [ "$HAS_DEPRECATED" != "" ]; then
      warn "VS Code settings.json still contains 'github.copilot.chat.codeGeneration.instructions'"
      info "Recommend removing it manually — the new instructions file mechanism will replace it"
      info "(if it has a Mac path on this machine, it WILL fail silently)"
    else
      ok "VS Code settings.json has no Copilot-instructions absolute path (good)"
    fi
  fi
else
  warn "VS Code user dir not found at: $VSCODE_USER_DIR"
  info "Install VS Code first, OR install.sh will skip the Copilot wiring step"
fi
echo ""

#— 8. Shell rc file ——————————————————————————————————————————————————
echo "[8] Shell rc (PATH for claude-handoff)"
SHELL_RC=""
if [ -f "$HOME/.zshrc" ] && [ ! -f "$HOME/.bashrc" ]; then
  SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
  SHELL_RC="$HOME/.bashrc"
elif [ -f "$HOME/.zshrc" ]; then
  SHELL_RC="$HOME/.zshrc"
fi
if [ -n "$SHELL_RC" ]; then
  RC_NAME=$(basename "$SHELL_RC")
  if grep -qF "$DOTFILES/bin" "$SHELL_RC" 2>/dev/null; then
    ok "~/$RC_NAME already has $DOTFILES/bin on PATH"
  else
    ok "~/$RC_NAME found; install.sh will append PATH update"
  fi
else
  warn "Neither ~/.zshrc nor ~/.bashrc found"
  info "You will need to manually add $DOTFILES/bin to your shell's PATH after install"
fi
echo ""

#— 9. Git config ——————————————————————————————————————————————————————
echo "[9] Git configuration"
if command -v git >/dev/null 2>&1; then
  GU=$(git config --global user.name 2>/dev/null || echo "")
  GE=$(git config --global user.email 2>/dev/null || echo "")
  [ -n "$GU" ] && ok "git user.name: $GU" || warn "git user.name not set globally"
  [ -n "$GE" ] && ok "git user.email: $GE" || warn "git user.email not set globally"
fi
echo ""

#— Summary ————————————————————————————————————————————————————————————
echo "==============================="
echo "Summary: $PASS pass, $WARN warn, $FAIL fail"
echo "==============================="
if [ $FAIL -gt 0 ]; then
  echo ""
  echo "✗ NOT SAFE TO INSTALL — fix the failures above first."
  exit 1
elif [ $WARN -gt 0 ]; then
  echo ""
  echo "⚠ Safe to install, but review the warnings above first."
  echo "  Most warnings are about backups (existing files will be moved aside, not deleted)"
  echo "  or accumulated state in settings.json that won't survive the regen."
  echo ""
  echo "  If you accept the warnings: ./install.sh"
  exit 0
else
  echo ""
  echo "✓ All clear. Run: ./install.sh"
  exit 0
fi
