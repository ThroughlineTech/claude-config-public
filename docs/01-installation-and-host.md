# 01 — Installation and Host Requirements

How a host gets from `git clone claude-config` to a Claude Code session
that can run `/ticket-chain` against a real Plane instance.

## install.sh — what it does, in order

[install.sh](../../install.sh) is idempotent and runs as a single bash
script. Every non-trivial step gates on a tool's availability and falls
back with a warning rather than failing hard.

### 1. Worktree refusal (lines 20–37)

If `install.sh` is invoked from a git worktree (not the main checkout),
it refuses and exits with a pointer to the main repo path. Symlinks
written from a worktree would dangle the moment `/ticket-ship` reaped
the worktree. This is the CCONF-14 fix called out in the script
comment.

**Status:** Functional. Hard exit on detect.

### 2. Symlink propagation to `~/.claude/` (lines 41–70)

`link()` is the helper at lines 42–56. It backs up any pre-existing
non-symlink target to `<dst>.backup.<TS>` and replaces it with a real
symlink. Idempotent: a matching existing symlink is a no-op.

Targets installed into `~/.claude/`:

| Source (in repo) | Symlink at | Used by |
|---|---|---|
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | every Claude session (auto-loaded) |
| `plan-mode.md` | `~/.claude/plan-mode.md` | `/ticket-investigate` line 34 reads it |
| `brainstorm-mode.md` | `~/.claude/brainstorm-mode.md` | `/brainstorm` line 12 reads it |
| `commands/` | `~/.claude/commands/` | every slash command |
| `plans/` | `~/.claude/plans/` | `bin/claude-handoff` |
| `brief-templates/` | `~/.claude/brief-templates/` | `/ticket-delegate` line 45 |
| `agents/` | `~/.claude/agents/` | `/op-run` cites these via heading-anchor URLs |
| `operation-templates/` | `~/.claude/operation-templates/` | `/op-scaffold` references for plan generation |

**Status:** Functional.

**Windows note (lines 8–10):** sets `MSYS=winsymlinks:nativestrict` so
Git Bash creates real Windows symlinks. Without this, `ln -s` on Git
Bash creates regular files that fail `[ -L ]`. Requires Developer Mode
in Windows Settings.

### 3. Alias wrapper generation (lines 76–158)

Reads [commands/aliases.map](../../commands/aliases.map) and emits a
real `.md` file (not symlink) for each alias into `commands/`. Each
wrapper is two lines of frontmatter plus a delegating body that
forwards `$ARGUMENTS` to the canonical command. The 14 declared
aliases:

```
tn  ticket-new        tl  ticket-list      ts  ticket-status
ti  ticket-investigate ta  ticket-approve   tr  ticket-review
tp  ticket-preview    tb  ticket-batch     tsh ticket-ship
td  ticket-defer      tc  ticket-close     tro ticket-reopen
tch ticket-chain      tcl ticket-cleanup
```

These files are appended to `.gitignore` automatically (lines
132–157) so they exist per-machine without committing. Real files (not
symlinks) because the Claude Code harness dedupes symlinked commands —
documented at [commands/aliases.map:11-13](../../commands/aliases.map).

**Status:** Functional. Cleanup of legacy alias-symlinks at line 82–88.

### 4. Settings merge (lines 160–188)

Picks `settings.<platform>.json` (Mac for `Darwin`/`Linux`; Windows for
`MINGW`/`MSYS`/`CYGWIN`) and merges into base via:

```
jq -s '
    .[0] as $base | .[1] as $plat |
    ($base * $plat)
    | .permissions.allow = (($base.permissions.allow // []) + ($plat.permissions.allow // []))
    | .permissions.deny  = (($base.permissions.deny  // []) + ($plat.permissions.deny  // []))
'
```

The merge concatenates allow + deny lists; everything else (env,
effortLevel, hooks) takes the platform value if present, otherwise base.

**Base contents** ([settings.base.json](../../settings.base.json)):
- `effortLevel: "max"`
- `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"`
- `includeCoAuthoredBy: false` and empty `attribution.commit`/`pr` —
  matches the no-Claude-branding rule at `~/.claude/CLAUDE.md` (universal
  conventions section).
- A baseline allow set for read-only Bash + git/gh/npm/python3/node/jq
  + WebSearch + WebFetch on three trusted domains.
- Deny set: `rm -rf` against root paths, `chmod`, `wget`, `sudo`.
- A `UserPromptSubmit` hook that invokes
  `~/.claude/hooks/surface-intercom-replies.sh` if it's executable.
- An `extraKnownMarketplaces` entry for the official Anthropic plugins
  marketplace.

**Mac additions** ([settings.mac.json](../../settings.mac.json)): Xcode
toolchain (`xcodebuild`, `xcrun`, `xcrun simctl`, `xctrace`,
`devicectl`, `instruments`, `plutil`), `open`, `swift`, `brew`, system
inspectors, `launchctl`, `systemctl`. `Read(/Applications/**)`,
`Read(/Volumes/**)`.

**Windows additions** ([settings.windows.json](../../settings.windows.json)):
`powershell`, `cmd`, `taskkill`, `where`, `wsl`, `schtasks`,
`Read(/c/Users/**)`, `Read(/c/src/**)`.

**Status:** Functional. If `jq` isn't installed, the merge is skipped
and a warning printed (line 174–175). If a non-symlink existing
settings.json is present, it's backed up first (line 177–179).

### 5. Copilot prompt mirrors (lines 190–236)

Three generated files in `copilot-prompts/`:

- `claude-global.instructions.md` — copy of `CLAUDE.md` with an
  `applyTo: "**"` frontmatter wrapper. Generated at line 193–199.
- `plan-mode.instructions.md` — same wrapper around `plan-mode.md`.
- `brainstorm-mode.instructions.md` — same around `brainstorm-mode.md`.

Then [bin/sync-copilot-prompts](../../bin/sync-copilot-prompts) is run
(lines 228–235). That script regenerates per-command Copilot prompt
files in `copilot-prompts/*.prompt.md` from the canonical Claude
command bodies under `commands/`.

**Status:** Functional. If `bin/sync-copilot-prompts` is missing, a
warning is printed but install continues.

### 6. VS Code Copilot wiring (lines 238–258)

Symlinks every `copilot-prompts/*.md` into the VS Code user prompts
directory. Per-platform path:

- Mac: `~/Library/Application Support/Code/User/prompts/`
- Linux: `~/.config/Code/User/prompts/`
- Windows: `$APPDATA/Code/User/prompts/`

If VS Code isn't installed (no user dir), the step is skipped with a
notice (line 257). No fallback for VS Code Insiders or alternate
installs.

**Status:** Functional. Loose end: only stable VS Code is wired.

### 7. PATH update (lines 260–302)

Picks `~/.zshrc` or `~/.bashrc` (preferring zsh on Mac, bash on Git
Bash). Appends `export PATH="$DOTFILES/bin:$PATH"` if not already
present. `chmod +x` on every file in `bin/`.

**Status:** Functional.

### 8. Intercom subsystem (lines 304–402)

Three sub-steps:

1. **Symlink `bin/*` → `~/bin/*`** (lines 316–320). Mirrors every
   helper. Also symlinks `hooks/surface-intercom-replies.sh` to
   `~/.claude/hooks/`.
2. **`mosquitto_pub` availability check** (lines 326–333). Warns if
   missing; no fallback (the helpers literally call `mosquitto_pub`).
3. **Creds prompt** (lines 336–364) — interactive only. Reads MQTT
   host/port/user/password and writes `~/.config/intercom/creds`
   chmod 600. Skipped if non-interactive (`-t 0` test).
4. **Windows-only Task Scheduler registration** (lines 367–389).
   Renders [windows/intercom-inbox-listener.xml.template](../../windows/intercom-inbox-listener.xml.template)
   into `windows/intercom-inbox-listener.xml.rendered` (substitutes
   `{{WINDOWS_USER}}` with `$USERNAME`). Then `schtasks /Create /XML`
   to register the listener task. The `MSYS_NO_PATHCONV=1` env at line
   379 prevents Git Bash from mangling `/Create` flags into POSIX
   paths.
5. **Surgical .mcp.json cleanup** (lines 391–400). If
   `~/.claude/.mcp.json` exists and contains a `mcpServers.intercom`
   entry, that entry is deleted. Leftover from the TKT-001 HTTP-era
   install.

**Status:** Functional. Loose ends: (a) the creds prompt is interactive
only; CI runs need a pre-written `creds` file. (b) Windows Task
Scheduler registration silently fails if `schtasks` isn't on PATH.

### 9. Plane MCP registration (lines 404–487)

The block requires:
- `secrets/.env` with `PLANE_BASE_URL`, `PLANE_API_KEY`,
  `PLANE_WORKSPACE_SLUG`. The `secrets/` dir is gitignored (`.gitignore`).
- `jq` on PATH.
- `uvx` on PATH (the Plane MCP server is invoked as `uvx
  plane-mcp-server stdio`).
- A pre-existing `~/.claude.json` (created on first `claude` run; if
  absent, install warns at line 451–453 and skips Plane registration).

When all four hold, the block writes:

1. **Claude Code user scope** (lines 440–453). Merges into
   `~/.claude.json`'s `mcpServers.plane`:
   ```json
   {
     "type": "stdio",
     "command": "uvx",
     "args": ["plane-mcp-server", "stdio"],
     "env": { "PLANE_BASE_URL": "...", "PLANE_API_KEY": "...", "PLANE_WORKSPACE_SLUG": "..." }
   }
   ```
   Note: the command is the literal string `"uvx"`, not an absolute
   path. This is by design (lines 434–436): a stale config copied
   between machines (Mac → Windows) would otherwise pin to the wrong
   absolute path.
2. **Copilot / VS Code user scope** (lines 455–483, CCONF-25).
   Different from the Claude Code entry. Copilot's token budget
   (Haiku 4.5 at 0.3× model weight) was overwhelmed by all 109 tools
   from `plane-mcp-server`, causing silent truncation that dropped
   write tools like `create_work_item`. Fix: Copilot is routed through
   a filtering proxy at `bin/plane-mcp-proxy.py` that intercepts
   `tools/list` JSON-RPC responses and passes through only the 17
   tools the ticket workflow actually calls.

   Entry written under `servers.plane` in `$VSCODE_USER_DIR/mcp.json`:
   ```json
   {
     "command": "uv",
     "args": ["run", "--no-project", "/abs/path/to/bin/plane-mcp-proxy.py"],
     "env": { "PLANE_BASE_URL": "...", "PLANE_API_KEY": "...", "PLANE_WORKSPACE_SLUG": "..." }
   }
   ```
   On Windows, `cygpath -m` converts the POSIX proxy path to a
   `C:/…/bin/plane-mcp-proxy.py` form that VS Code can spawn.

   The Claude Code entry (`.mcpServers.plane` in `~/.claude.json`)
   remains `uvx plane-mcp-server stdio` with the full 109-tool schema.
   The two registrations intentionally differ: terminal sessions handle
   the full schema; Copilot's Haiku-backed tool picker cannot.
3. **`~/.claude/plane-config.md`** (lines 482–485). A *global*
   credentials file that the TravelAgent extension reads at line 144
   of [extension/src/api/planeClient.ts](../../extension/src/api/planeClient.ts).
   Three lines: `- API URL: ...`, `- API key: ...`, `- Workspace slug: ...`.
   This file is **not** the per-project `<workspace>/.claude/plane-config.md`
   that `/ticket-install` writes. The two are distinct; the
   relationship is documented in
   [02-ticket-install-and-workspace-contract.md](02-ticket-install-and-workspace-contract.md)
   and [06-extension-and-external-contracts.md](06-extension-and-external-contracts.md).

**Status:** Functional. The duplication of credentials between
`~/.claude.json` (Plane MCP env), `~/Library/Application Support/Code/User/mcp.json`
(Copilot MCP env), and `~/.claude/plane-config.md` (TravelAgent
extension's source for the same secrets) is the cost of keeping three
consumers in sync from one input file.

### 10. Extension compile (lines 489–508)

Conditional on `extension/node_modules/` existing. If so, runs
`npm run compile` (which invokes `tsc -p ./` per
[extension/package.json:301](../../extension/package.json)). The
extension's `dist/extension.js` and `dist/travelagent.vsix` are
regenerated.

**Status:** Functional. First-time installs need a manual `cd
extension && npm install` first; the script does not bootstrap
node_modules. Loose end: no `npm ci` for reproducibility.

### 11. Smoke tests (lines 510–619)

Verifies every symlink target exists, every dispatched command file is
visible through the symlink, and every `commands/{ticket,plan}-*.md`
contains the literal string `"Pre-flight: detect backend"` —
`ticket-install.md` exempt at line 547–548. The dispatch-block check
fails the install if any command file is missing the section, because
silently-defaulting commands lose the dual-world dispatch.

Other smoke checks:
- `effortLevel == "max"` in the merged settings.json.
- Plane MCP command host-compatibility (Windows host shouldn't have a
  POSIX-only command, vice versa). Lines 575–618.
- Copilot proxy wiring: `mcp.json` `servers.plane.command` equals `uv`
  and `servers.plane.args[1]` ends with `plane-mcp-proxy.py`. Added
  in CCONF-25.
- Intercom: `~/bin/send-job` symlink, hook symlink,
  `~/.config/intercom/creds` presence (warn-only).

**Status:** Functional.

## preflight.sh — read-only safety check

[preflight.sh](../../preflight.sh) runs before `install.sh` and
confirms the host can install without surprises. It mutates nothing.
Nine numbered checks:

1. **Platform detection** (lines 24–34). Mac / Linux / Git Bash /
   unknown.
2. **Required tools** (lines 36–50). `git`, `jq`, `ln`, `readlink`,
   `chmod`, `mkdir`, `grep`. Missing `jq` is the most common gap;
   error message gives the install command per platform.
3. **Symlink capability** (lines 52–84). Creates a tmp file, symlinks
   it, reads the link back. On Git Bash without
   `MSYS=winsymlinks:nativestrict`, this catches the fake-symlink
   regression.
4. **Repo files all present** (lines 86–105). 22 expected files
   including `commands/ticket-install.md`, `bin/claude-handoff`, and
   each brief template.
5. **What install.sh would back up** (lines 107–134). Walks
   `~/.claude/{CLAUDE.md, plan-mode.md, brainstorm-mode.md, commands,
   plans, brief-templates, settings.json}` and reports — for each —
   whether it's already linked correctly (no-op), a stray file (will
   be backed up), or absent (clean install).
6. **Existing settings.json analysis** (lines 137–164). Counts allows,
   denies, additionalDirectories; reports `effortLevel` and the
   experimental-teams env var. Warns that accumulated allows in the
   live `settings.json` will not survive the regen.
7. **VS Code detection** (lines 166–245). Confirms the user dir
   exists, lists existing prompt files, warns if the deprecated
   `github.copilot.chat.codeGeneration.instructions` setting is still
   present in VS Code's settings.json. Also checks Plane MCP command
   compatibility against the current platform (Windows-flavored
   command on a Mac is a stale config copy).
8. **Shell rc file** (lines 247–268). Confirms either `~/.bashrc` or
   `~/.zshrc` exists and notes whether `bin/` is already on PATH.
9. **Git config** (lines 270–278). `user.name`/`user.email` set
   globally — warns if missing.

Exit codes: `0` if zero failures and zero warnings; `0` (with a
message) if warnings only; `1` if any failure.

**Status:** Functional.

## Host requirements (concretely)

The minimum a host must have to run a clean install:

| Requirement | Why | Where checked |
|---|---|---|
| `git` | Symlinks via repo, version control | preflight `[2]` |
| `jq` | Settings merge, MCP config edits | preflight `[2]` + install line 173 |
| `bash` 4+ | Both scripts use POSIX bash + arrays | implicit |
| Symlink capability | Repo→`~/.claude` | preflight `[3]` |
| `~/.zshrc` or `~/.bashrc` | PATH update target | preflight `[8]`, install line 257 |
| Optional: `mosquitto_pub` | Intercom dispatch | install line 326 |
| Optional: `uvx` (uv) | Plane MCP server transport | install line 431 |
| Optional: `npm` + `node_modules/` | Extension compile | install line 498 |
| Optional: VS Code | Copilot prompt mirroring + MCP wiring | install line 249 |
| Optional: `secrets/.env` with three Plane env vars | Plane MCP registration | install line 417 |
| Optional: Pre-existing `~/.claude.json` | Plane MCP registration target | install line 440 |

The "optional" items each gate independently and skip with a warning.
A host with none of them still gets a working symlinked-commands
install.

**Windows-specific extras:**
- Developer Mode ON (or admin) for real symlinks. Preflight catches
  the absence at `[3]`.
- `schtasks` for the intercom listener Task Scheduler registration.
- `MSYS_NO_PATHCONV=1` env recommended for any command that takes
  flags starting with `/` — install line 379 sets it for `schtasks`;
  the TravelAgent extension's terminal launcher sets it for
  `/ticket-*` commands at
  [extension/src/actions/ticketActions.ts:147](../../extension/src/actions/ticketActions.ts).

## MCP server requirements

claude-config requires exactly one MCP server: **`plane`** (stdio,
Python `plane-mcp-server` shipped via `uvx`). Lines 441–447 of
`install.sh` register it. Tools used by claude-config commands:

| Tool name | First call site (file:line) | Used by |
|---|---|---|
| `mcp__plane__get_me` | `commands/ticket-install.md:37` | `/ticket-install` MCP reachability check |
| `mcp__plane__list_projects` | `commands/ticket-install.md:40` | project picker |
| `mcp__plane__create_project` | `commands/ticket-install.md:42` | new-project flow |
| `mcp__plane__list_states` | `commands/ticket-install.md:62` | state seeding |
| `mcp__plane__create_state`, `update_state` | `commands/ticket-install.md:69-71` | state seeding + sequence pin |
| `mcp__plane__list_labels`, `create_label` | `commands/ticket-install.md:74,85` | workspace + app label seeding |
| `mcp__plane__retrieve_work_item_by_identifier` | `commands/ticket-investigate.md:52`, every other ticket-* command | exact-match lookup with `expand="labels,state"` |
| `mcp__plane__retrieve_work_item` | `commands/ticket-investigate.md:67` | parent fetch |
| `mcp__plane__create_work_item` | `commands/ticket-new.md:77` | new ticket |
| `mcp__plane__update_work_item` | `commands/ticket-investigate.md:132`, every state-changing command | state, labels, description_html |
| `mcp__plane__create_work_item_comment` | `commands/ticket-investigate.md:134` (`[investigated_at: <sha>]`), `commands/ticket-defer.md:38` (`deferred:`), `commands/ticket-close.md:38` (`wontfix:`), `commands/ticket-reopen.md:44` (`reopened:`), `commands/ticket-preview.md:40` (`[preview]`), `commands/ticket-delegate.md:60` (`[delegated_to: ...]`), `commands/ticket-collect.md:48` (`[collected]`), `commands/plan-new.md:62` (open questions), `commands/plan-verify.md:52` (judgment) | every load-bearing comment marker |
| `mcp__plane__list_work_item_comments` | `commands/ticket-status.md:49` | lifecycle reconstruction |
| `mcp__plane__list_work_item_activities` | `commands/ticket-status.md:49` | lifecycle reconstruction |
| `mcp__plane__list_work_item_relations` | `commands/ticket-investigate.md:169`, `commands/ticket-chain.md:53` | declared deps + native `blocked_by`/`blocking`/`relates_to` |
| `mcp__plane__create_work_item_relation` | `commands/ticket-new.md:111-118` | `--follow-up`, `--blocks`, `--blocked-by`, `--duplicate-of` flags + implicit prose detection |
| `mcp__plane__list_work_items` | `commands/ticket-chain.md:36`, `commands/ticket-batch.md:39`, `commands/plan-verify.md:32` | bounded batch fetches; `plan-verify` uses `fields=` to drop description bytes |
| `mcp__plane__list_work_item_links`, `create_work_item_link` | `commands/ticket-ship.md:82`, `commands/plan-verify.md:33` | PR link attachment + retrieval |

**Handshake when Plane MCP is unreachable:** `/ticket-install` checks
`mcp__plane__get_me` first ([commands/ticket-install.md:37](../../commands/ticket-install.md))
and stops with a tailored message pointing at `secrets/.env` +
`./install.sh`. Other commands assume the MCP is present once
`.claude/plane-config.md` exists; if a tool call fails at runtime, the
command body's "Rules" section governs (e.g. `/ticket-investigate`'s
"Rules (Plane path)" at line 187–194 forbids unbounded fallback
fetches).

claude-config does **not** depend on:

- Filesystem MCP (commands use the built-in `Read`/`Edit`/`Write`/`Glob`
  /`Grep` tools).
- Throughline's HTTP API. The TravelAgent extension reads typed-state
  from Throughline, but no claude-config command calls
  `interview.throughlinetech.net` directly. See
  [06-extension-and-external-contracts.md](06-extension-and-external-contracts.md).
- Any other MCP server. The intercom subsystem talks to MQTT directly
  via `mosquitto_pub`/`mosquitto_sub` (not via an MCP shim — `install.sh`
  line 391–400 actively *removes* a leftover intercom MCP entry from
  prior eras).

## Uninstall

There is no `uninstall.sh`. Removal is manual:

1. Delete the symlinks from `~/.claude/` and `~/bin/`.
2. Delete the merged `~/.claude/settings.json`.
3. `jq 'del(.mcpServers.plane)'` on `~/.claude.json`.
4. Remove the Copilot prompt symlinks under
   `$VSCODE_USER_DIR/prompts/` and the `.servers.plane` entry from
   `$VSCODE_USER_DIR/mcp.json`.
5. On Windows: `schtasks /Delete /TN intercom-inbox-listener /F`.
6. Rip the `bin/` PATH line from your shell rc.
7. Generated alias `.md` files in `commands/tn.md`, `commands/tl.md`, etc. live
   in the repo (gitignored) and persist until the repo is deleted.

The smoke-test logic in `install.sh:519-567` does not have a
counterpart that *removes* the configuration — `install.sh` is a
forward-only mutator.

**Status:** Aspirational uninstall only. The fact that everything
goes through `link()` (a backup-then-symlink helper) means manual
cleanup can be reversed via the `.backup.<TS>` files left behind, but
that's coincidence, not a designed rollback.

## Loose ends

- **No `npm ci` for the extension.** First-time installs need
  `cd extension && npm install` manually before `install.sh` will
  compile. The script silently skips compile if `node_modules/` is
  absent; nothing prompts for it.
- **`~/.claude/plane-config.md` (global, three lines) versus
  `<workspace>/.claude/plane-config.md` (per-project, full schema)
  collision.** Both files have the same name. The extension's path
  resolver
  ([extension/src/api/planeClient.ts:144-163](../../extension/src/api/planeClient.ts))
  reads both, with workspace overriding global. `/ticket-install`
  only writes the workspace version. `install.sh` only writes the
  global version. There's no documentation that explains the schema
  difference; readers infer it from the code.
- **Auto-migration of old creds.** The `planeClient.ts` migration at
  lines 44–137 silently strips a legacy `- Api Key:` line from any
  `plane-config.md` it finds, moving the value to VS Code
  SecretStorage. This runs at extension activation, not at
  `install.sh` time. So a host that runs `install.sh` but never opens
  VS Code never gets the migration, and the legacy file persists
  with the plaintext key.
- **Windows-only Task Scheduler.** No equivalent on macOS / Linux. The
  intercom listener is not started automatically there; the user runs
  `intercom-inbox-listener` manually or symlinks it into a launchd /
  systemd unit by hand. `docs/intercom-runbook.md` is the operational
  doc; install does not touch it.
- **`extraKnownMarketplaces.claude-plugins-official` in
  settings.base.json.** The base settings declare a plugin marketplace
  pointing at `anthropics/claude-plugins-official`. No claude-config
  command references it; the entry exists but is unused by the
  worker layer. If a user has subscribed to plugins from that
  marketplace, they appear in their Claude Code session — that's
  outside the scope of this repo.
