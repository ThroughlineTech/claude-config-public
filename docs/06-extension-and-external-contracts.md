# 06 — Extension and External Contracts

What claude-config reads/writes that other repos also touch, and what
it does not. Specifically:

- Contract with the TravelAgent VS Code extension (lives in this repo
  under [extension/](../../extension/)).
- Contract with throughline-interview-v2 (the producer tier).
- State and persistence — every file claude-config writes during
  worker activity.

## Where the extension lives

[extension/](../../extension/) is a self-contained TypeScript VS Code
extension that compiles to `extension/dist/extension.js` via
`install.sh:489-508`. Its own state-of-system docs are at
[extension/docs/state-of-the-system/](../../extension/docs/state-of-the-system/)
— that set is the canonical broker-tier reference (six docs,
2026-05-07).

This section covers only the **claude-config side** of the contract:
what claude-config commands assume the extension has done, what
claude-config writes that the extension reads, and what neither side
touches.

## The shared workspace contract

A workspace where both halves operate has these files in `.claude/`:

| File | Owner(s) | Schema | Notes |
|---|---|---|---|
| `plane-config.md` | Both | See [02-ticket-install-and-workspace-contract.md](02-ticket-install-and-workspace-contract.md) | Two writers; conflicting expectations covered below |
| `ticket-config.md` | `/ticket-install` only | Per-project workflow config | Extension reads but does not write |
| Workspace `CLAUDE.md` | Both (append-only) | Free-form | Extension does not modify; `/ticket-install` appends `## Tickets` if absent |

Plus `.gitignore` entry for `.worktrees/` (added by `/ticket-install`
Phase P7).

### `plane-config.md` — the two-writer file

`<workspace>/.claude/plane-config.md` is written by **two different
processes**, and their writes have different shapes.

**Stub write — TravelAgent `bindProject`** ([extension/src/api/planeClient.ts:202-232](../../extension/src/api/planeClient.ts)):

```typescript
function saveProjectIdToWorkspace(projectId: string) {
  const workspaceFolders = vscode.workspace.workspaceFolders;
  if (!workspaceFolders || workspaceFolders.length === 0) return;

  const claudeDir = path.join(workspaceFolders[0].uri.fsPath, '.claude');
  const configPath = path.join(claudeDir, 'plane-config.md');

  if (!fs.existsSync(claudeDir)) {
    fs.mkdirSync(claudeDir, { recursive: true });
  }

  if (fs.existsSync(configPath)) {
    let contents = fs.readFileSync(configPath, 'utf8');
    if (/^- Project ID:\s*.+$/m.test(contents)) {
      contents = contents.replace(/^- Project ID:\s*.+$/m, `- Project ID: ${projectId}`);
    } else {
      contents = contents.trimEnd() + `\n- Project ID: ${projectId}\n`;
    }
    fs.writeFileSync(configPath, contents, 'utf8');
  } else {
    const contents = `# Plane Backend Config

Presence of this file switches ticket commands to the Plane backend.
Written by TravelAgent extension.

- Backend: plane
- Project ID: ${projectId}
`;
    fs.writeFileSync(configPath, contents, 'utf8');
  }
}
```

This minimal stub:
- Switches the dispatch block in every ticket-* command into the
  Plane path (because the file's presence is the only test;
  `commands/ticket-investigate.md:12`).
- Has only `Backend:` and `Project ID:` fields. No state IDs, no
  label IDs, no view URLs, no workspace slug, no project identifier.
- Is **idempotent in update mode** — preserves any prior content
  except the one `- Project ID:` line, which it rewrites in place.

**Canonical write — `/ticket-install` Phase P5**: full schema
documented at
[02-ticket-install-and-workspace-contract.md](02-ticket-install-and-workspace-contract.md#phase-p5-write-claudeplane-configmd-lines-152225).
Includes state IDs, label IDs, view URLs, workspace slug, project
identifier, state/label sections.

**Why the two coexist:**

The TravelAgent extension's `bindProject` is for users who want
to associate a workspace with a Plane project quickly (the dispatch
gate alone is enough for the extension's UI to function — it reads
projectId out of this stub and uses its own REST client to talk to
Plane). It does NOT need state UUIDs for its own operation; it
fetches them from Plane on demand.

`/ticket-install` is for users who want the slash commands to work in
that workspace. The slash commands need state UUIDs to call
`update_work_item(state=<uuid>)`. Without the canonical file, every
slash command would have to call `mcp__plane__list_states` on every
invocation — wasteful and slow.

**Reconciliation:** the recommended path is

1. Run TravelAgent `bindProject` (writes stub).
2. Run `/ticket-install` from the same workspace (writes canonical;
   detects "already on Plane" via the stub's `- Backend: plane`
   line and routes through update mode).

The TravelAgent extension surfaces a "Bootstrap Ticket Workflow"
command (`travelagent.bootstrapTicketWorkflow` —
[extension/package.json:186-188](../../extension/package.json)) that
opens a terminal in the workspace folder and pre-types
`claude /ticket-install` — see
[extension/src/actions/ticketActions.ts:160-181](../../extension/src/actions/ticketActions.ts).
The extension never replicates `/ticket-install` logic; it only opens
the right launcher.

**Conflict scenarios:**

- TravelAgent stub written first, `/ticket-install` runs second:
  `/ticket-install` Phase P1 step 1 detects "already on Plane → update
  mode" and offers to overwrite. With user confirmation, the canonical
  schema is written.
- `/ticket-install` written first, TravelAgent `bindProject` runs
  later: extension's update path preserves all existing content
  except for the `- Project ID:` line. Safe for everything except
  rebinding to a different project, which would invalidate the
  state/label UUIDs the canonical file holds.
- Both write at the same time: race condition. No file lock. Last
  writer wins.

### `~/.claude/plane-config.md` (global) — separate file

A different file with the same name lives at the user's home
directory. Written by `install.sh:482-485` with three lines:

```
# Plane Agent Config
# Generated by install.sh.

- API URL: {PLANE_BASE_URL}
- API key: {PLANE_API_KEY}
- Workspace slug: {PLANE_WORKSPACE_SLUG}
```

Read by the TravelAgent extension at
[extension/src/api/planeClient.ts:144](../../extension/src/api/planeClient.ts).
Provides the credentials the extension uses for its REST client.

**Migration** at [extension/src/api/planeClient.ts:44-137](../../extension/src/api/planeClient.ts):
on extension activation, if any `plane-config.md` is found with a
literal `- Api Key:` line in plaintext, the line is stripped and the
value moved into VS Code's SecretStorage. Logged. Non-fatal.

claude-config slash commands do NOT read `~/.claude/plane-config.md`.
They read the workspace `.claude/plane-config.md` for project IDs and
they read `~/.claude.json` for `mcpServers.plane.env.PLANE_WORKSPACE_SLUG`
in three commands (`/ticket-list`, `/ticket-status`, `/ticket-promote`)
when the workspace file is missing the cached `## View URLs`.

## Throughline-v2 contract: not implemented in claude-config

The throughline-interview-v2 README contract names "TravelAgent's
coordinator (or future agents)" as the consumer of two endpoints:

- `POST /api/projects/:id/fulfillments` — record that a deliverable's
  acceptance criterion was satisfied by a specific PR/commit.
- `GET /api/projects/:id/fulfillments` — read those records.

Neither endpoint is called by any claude-config slash command.
Confirmation:

```
$ grep -rn "fulfillment\|fulfill" commands/
(no matches)
```

The TravelAgent extension also doesn't post fulfillment records (per
its set-2 docs at
[extension/docs/state-of-the-system/05_throughline_back_channel.md](../../extension/docs/state-of-the-system/05_throughline_back_channel.md)
and the archived plan at
[extension/docs/archive/operation-pipeline/followup-03-operation-verification.md](../../extension/docs/archive/operation-pipeline/followup-03-operation-verification.md):
"The Coordinator's PR-time verification job is explicitly *not* in
scope" — followup-03 is the unbuilt plan).

So the answer to the prompt's question 7:

> Does any command in claude-config post fulfillment records back
> to throughline-v2 via POST /api/projects/:id/fulfillments?

**No.** Neither claude-config nor the TravelAgent extension implements
that POST. The throughline-v2 contract names a future-agent surface
that does not exist yet on either side. Whoever ships
followup-03-operation-verification next is the future agent.

### What claude-config does NOT read from Throughline

- No claude-config command calls `interview.throughlinetech.net`.
- No claude-config command reads typed-state JSON. The TravelAgent
  extension reads typed-state via its
  [throughlineClient.ts](../../extension/src/api/throughlineClient.ts)
  HTTP client; that client is not exposed to claude-config commands.
- claude-config has no `bin/` helper that talks to throughline-v2.

The producer/broker/worker tiers are decoupled at this layer:
typed-state flows producer → broker → Plane via HTTP/REST; the
worker tier (claude-config) only sees the Plane state. By design, a
claude-config session that runs `/ticket-chain` against a Plane
workspace seeded by the broker doesn't know whether the work items
came from typed-state shred or from manual `/ticket-new` calls. The
work items are identical in shape; only their `description_html`
markers differ ("From: throughline" vs absent).

## What `/ticket-chain` assumes about the workspace

Question 9 from the prompt. Beyond "is a git repo," the assumptions:

| Assumption | Where enforced |
|---|---|
| `.claude/plane-config.md` OR `.claude/ticket-config.md` exists | dispatch block top of every command |
| `.claude/ticket-config.md` has `Test`, `Build` (and optionally `Deploy`, `Lint`) commands populated | `commands/ticket-chain.md:28`; `commands/ticket-batch.md:28` |
| Working tree is clean | `commands/ticket-chain.md:29` |
| Currently on the trunk branch (`main` by default) | `commands/ticket-chain.md:29` |
| The trunk branch is `main` (or `Main branch:` is set) | `commands/ticket-install.md:21-29`; `commands/ticket-approve.md:43`; warns if `master` |
| `.worktrees/` is gitignored | `commands/ticket-install.md:286-289`; `commands/ticket-chain.md:46` |
| Plane MCP `plane` server is registered + reachable | every Plane-path command |
| The schema seeded by `/ticket-install` is intact (state UUIDs, label UUIDs) | every Plane-path command reads `.claude/plane-config.md` |

**Stack-specific code paths in command bodies:**

| Stack | Where it appears |
|---|---|
| Node / npm / pnpm / yarn | `commands/ticket-install.md:97-99` (marker file detection); preview-profile detection table at line 113 |
| Rust (Cargo) | `commands/ticket-install.md:99` |
| Go | `commands/ticket-install.md:100` |
| Swift / Xcode | `commands/ticket-install.md:101`; line 121 (multi-scheme detection); `commands/ticket-install.md:380-382` (markdown path) |
| Python (pyproject + requirements) | `commands/ticket-install.md:102-103` |
| Ruby | `commands/ticket-install.md:104` |
| Java (Maven, Gradle) | `commands/ticket-install.md:105` |
| Generic Makefile | `commands/ticket-install.md:106` |
| Docker Compose | `commands/ticket-install.md:119` |
| Vercel / Netlify | `commands/ticket-install.md:120` |

After `/ticket-install` runs, **the rest of the command bodies are
stack-agnostic.** They read commands from
`.claude/ticket-config.md` rather than embedding stack assumptions.
For example, `/ticket-approve` Phase 3 calls "the Test command"
(line 70) without caring whether it's `npm test` or `cargo test` or
`xcodebuild test`.

The Windows-specific affordance — `MSYS_NO_PATHCONV=1` env when
spawning Git Bash —
[extension/src/actions/ticketActions.ts:147](../../extension/src/actions/ticketActions.ts) —
is set by the launcher, not the slash command. So a Mac shell or a
Windows shell launching `claude /ticket-chain ...` directly works the
same, but a Mac+Windows-mixed CI pipeline that omits the env var
breaks slash names like `/ticket-*` into POSIX paths.

**No CI integration.** No claude-config slash command interacts with
GitHub Actions, GitLab CI, CircleCI, etc. `/ticket-ship`'s "Deploy"
step runs whatever local command is configured in
`.claude/ticket-config.md`'s `Deploy:` field. CI happens *after* push
on the host's CI provider; claude-config does not orchestrate it.

## State and persistence — what claude-config writes

Question 10. Every file claude-config touches during normal worker
operation:

### Inside the workspace (gitignored or version-controlled)

| Path | Lifecycle | Owner |
|---|---|---|
| `.claude/plane-config.md` | Created by `/ticket-install` Phase P5 (or by extension stub); read by every Plane-path command | committed |
| `.claude/ticket-config.md` | Created by `/ticket-install` (Phase P6 in Plane mode, Phase 5 in Markdown mode); read by every command for Test/Build/Deploy/Lint + preview profiles | committed |
| `tickets/TKT-NNN.md` (Markdown only) | Per-ticket; created by `/ticket-new`; moved between `tickets/`, `tickets/shipped/`, `tickets/deferred/`, `tickets/wontfix/` via `git mv` | committed |
| `tickets/stub/TKT-NNN.md`, `tickets/stub/EPIC-<slug>.md` | Created by `/brainstorm` at session-end; promoted to active set by `/ticket-promote` | committed |
| `tickets/{ID}.{phase-tag}.brief.md` | Created by `/ticket-delegate`; moved with the ticket file when it ships/defers | committed |
| `tickets/CHAIN-REVIEW-{YYYY-MM-DD-HHMM}.md` | Created by `/ticket-chain` Phase 4 in default mode; one per chain run | committed |
| `.worktrees/ticket-{lowercased-id}/` | Per-ticket worktree; created by `/ticket-chain` Phase 3A or `/ticket-batch` Phase 4; removed by `/ticket-ship` Phase 7, `/ticket-cleanup`, or `/ticket-defer`/`/ticket-close` decruft | gitignored (`.worktrees/`) |
| `.worktrees/ticket-{lowercased-id}/.preview.pid` | Per-component live PID line: `{component}  {pid}  {port}\n`; written by `/ticket-preview` Step 5; consumed by `/ticket-cleanup`, `/ticket-ship` Phase 7 | gitignored |
| `.worktrees/ticket-{lowercased-id}/.preview.meta` | Profile, components, started_at, branch; format unspecified | gitignored |
| `.worktrees/batch-preview-*/` | Rollup preview worktree; created by `/ticket-batch` rollup mode; reaped by `/ticket-cleanup` if older than 24h or `--all` | gitignored |
| `docs/operations/<slug>/` | Created by `/op-scaffold`; read+written by `/op-run`; never deleted automatically | committed |
| `docs/operations/<slug>/operation-state.json` | Live progress; updated at every state transition by `/op-run`; preserved across resumptions | committed (so the audit trail survives) |
| `docs/operations/<slug>/HANDOFF.md`, `VERIFY.md` | Created by `/op-run` at finalization | committed |
| `.briefs/` (fallback) | Created by `/ticket-delegate` when `tickets/` doesn't exist (Plane projects with no on-disk tickets) | gitignored if listed manually; not auto-added |

### Outside the workspace (host state)

| Path | Lifecycle | Owner |
|---|---|---|
| `~/.claude/CLAUDE.md`, `plan-mode.md`, `brainstorm-mode.md`, `commands/`, `agents/`, `brief-templates/`, `operation-templates/`, `plans/` | Symlinks; created by `install.sh` lines 63–70 | install.sh |
| `~/.claude/settings.json` | Merged by `install.sh:181-186` from base + platform JSON | install.sh |
| `~/.claude/hooks/surface-intercom-replies.sh` | Symlink; `install.sh:323` | install.sh |
| `~/.claude.json` (`.mcpServers.plane`) | Plane MCP registration; merged by `install.sh:441-448` | install.sh |
| `~/.local/state/intercom/inbox.jsonl` | Reply log; appended by `bin/intercom-inbox-listener` | listener daemon (Mac launchd / Windows Task Scheduler) |
| `~/.local/state/intercom/inbox.cursor` | Byte offset; advanced by `hooks/surface-intercom-replies.sh` | hook |
| `~/.config/intercom/creds` | MQTT broker credentials, chmod 600; written by `install.sh:336-364` interactively | install.sh |
| `~/.config/intercom/session` | `TARGET_MACHINE`, `TARGET_REPO`; written by `bin/intercom-session set` | `/register` |
| `~/.claude/plane-config.md` | Three-line credentials file; `install.sh:482-485` | install.sh |
| `~/bin/<helper>` | Symlinks for every `bin/<helper>`; `install.sh:316-320` | install.sh |
| `$VSCODE_USER_DIR/prompts/<name>.md` | Symlinks for every Copilot prompt mirror; `install.sh:249-258` | install.sh |
| `$VSCODE_USER_DIR/mcp.json` (`.servers.plane`) | Plane MCP for Copilot; `install.sh:456-479` | install.sh |
| `$DOTFILES/windows/intercom-inbox-listener.xml.rendered` | Rendered Task Scheduler XML; `install.sh:372-373` (Windows only) | install.sh |
| `$DOTFILES/copilot-prompts/*.instructions.md` | Generated mirrors; `install.sh:193-220` and `bin/sync-copilot-prompts` | install.sh |
| `$DOTFILES/commands/{tn,tl,ts,...}.md` | Generated alias wrappers; `install.sh:90-129`; gitignored | install.sh |

### What does NOT persist across sessions

- **Pasted images** in chat input. Plane MCP exposes no upload tool;
  the markdown ticket file is text-only. `/ticket-new` distills
  images into prose `Visual context` blocks at session time
  (`commands/ticket-new.md:60-62`).
- **Conversation history** of a Claude session. The session is the
  scratch space; files committed (or written under `.worktrees/`) are
  the artifact.
- **Live preview process state** beyond `.preview.pid`. The PID file
  records what was launched; reading it is the only way to find live
  processes after a session ends.
- **Operation transcripts.** `/op-run` writes to
  `operation-state.json` at every state transition but does NOT
  capture the conversation. Recovery on a crashed session is
  state-driven, not transcript-driven.

## What `claude-config` does *not* contain

To answer the prompt's question 8 cleanly, what's *not* in this repo:

- No HTTP client to `interview.throughlinetech.net`. That belongs to
  the TravelAgent extension's `throughlineClient.ts`, not to
  claude-config.
- No POST handler for `fulfillments`. Throughline-v2's contract
  names a consumer that doesn't exist on either side.
- No GitHub Actions workflow files. The repo isn't CI-driven.
- No `package.json` at the repo root (only inside `extension/`).
  claude-config itself isn't an npm package.
- No tests for slash commands. Only the extension has tests
  (`extension/src/**/*.test.ts`, vitest). Slash command bodies are
  not unit-testable — they're prompts.
- No daemon. Every command is invoked by the user explicitly. The
  hook (UserPromptSubmit → surface-intercom-replies.sh) is the only
  passive surface, and it's ~50 lines of bash.
- No web UI of its own. The Plane web UI is the canvas; claude-config
  hands off to it via View URLs.

## Loose ends

- **Plane MCP versioning.** The MCP server is invoked as `uvx
  plane-mcp-server stdio` (install.sh:445). No version pin. A breaking
  change to the MCP server's tool schema would silently break every
  command. There's no version check in `install.sh` smoke tests.
- **Workspace slug duplication.** `~/.claude/plane-config.md` (global,
  written by `install.sh`), `~/.claude.json` (env in `mcpServers.plane.env`),
  `<workspace>/.claude/plane-config.md` (per-project, written by
  `/ticket-install`) all hold the workspace slug. Three writers, one
  value. They're updated by separate paths and could drift.
- **TravelAgent stub vs canonical write race.** No locking on
  `.claude/plane-config.md`. Concurrent writes from extension UI and
  CLI session are not protected.
- **No back-channel from worker → broker.** When `/ticket-ship`
  transitions a work item to Done, the TravelAgent kanban view will
  pick it up on its next scheduler poll
  (`extension/src/coordinator/scheduler.ts`). There's no push from
  worker side. The broker is eventually consistent against Plane
  state, polling-driven.
- **No fulfillment-style audit trail in Plane.** When `/ticket-ship`
  attaches a PR link via `mcp__plane__create_work_item_link`, that's
  the only structured artifact. There's no per-acceptance-criterion
  fulfillment record. `/plan-verify` reconstructs principle-vs-PR
  judgments at audit time by parsing diffs; no per-criterion record
  is written back. The throughline-v2 fulfillments endpoint, if ever
  shipped, would be the natural target.
- **Throughline-v2 contract is the only "future agent" hook in the
  three-tier stack.** Without it, the worker tier is **terminal** —
  ship and stop. There's no path for a downstream consumer to know
  what shipped at the deliverable level (Plane states are work-item
  level; the deliverable / criterion abstraction lives in
  Throughline). This is the gap that followup-03 was meant to close.
- **Operation HANDOFF.md handoff is human-only.** When `/op-run`
  finishes, HANDOFF.md and VERIFY.md are committed; no service
  reads them. The user walks VERIFY.md before merging. No
  follow-up-ticket auto-creation from "Known limitations" or
  "Follow-up tickets opened" sections — the followup tickets were
  already created by `/ticket-new` during the residual disposition
  step (`commands/op-run.md:166`) and are referenced by ID in
  HANDOFF.md.
- **CCONF tickets in the parent repo's plane.** This claude-config
  repo itself uses Plane (identifier `CCONF`). Pulling the fence
  back: claude-config commands are running against a Plane workspace
  that holds tickets *for the same repo*. The recursion is fine in
  practice — `/ticket-investigate CCONF-21` runs as expected — but
  if `/ticket-install` were re-run, Phase P1's project picker would
  see CCONF among the projects and route through update mode.
