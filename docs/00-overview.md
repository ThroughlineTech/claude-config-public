# State of the System: claude-config

Date: 2026-05-09. Code-true at HEAD `d5318c7`. Where these docs and the
command bodies disagree, the command body wins.

This is the third part of a three-set architecture review:

1. `throughline-interview-v2/docs/state-of-the-system/` — the producer
   side (typed-state extractor; six docs, 2026-05-06).
2. TravelAgent VS Code extension state-of-the-system at
   [extension/docs/state-of-the-system/](../../extension/docs/state-of-the-system/)
   — the broker/monitor side (six docs, 2026-05-07).
3. **This set** — the worker layer. The actual slash command bodies that
   Claude Code executes when TravelAgent dispatches `/ticket-chain`, plus
   the bootstrap stack (`install.sh`, MCP wiring, Plane contract) that
   makes those commands runnable on a host.

The reader is expected to have all three sets open side by side.

## What claude-config is

`claude-config` is a personal dotfiles repo at `~/src/claude-config` that
serves three roles simultaneously:

- **Host bootstrap.** [install.sh](../../install.sh) symlinks
  `commands/`, `agents/`, `plan-mode.md`, `brainstorm-mode.md`,
  `CLAUDE.md`, `brief-templates/`, `operation-templates/`, and `plans/`
  into `~/.claude/` so Claude Code finds them; merges
  `settings.{base,mac,windows}.json` into `~/.claude/settings.json`;
  registers the Plane MCP server in `~/.claude.json` and in VS Code's
  Copilot `mcp.json`; symlinks the intercom helpers from `bin/` into
  `~/bin/`; and (if `node_modules/` is present) compiles the TravelAgent
  extension under [extension/](../../extension/).
- **Worker layer.** The contents of [commands/](../../commands/) — 40
  Markdown files plus the alias map — are universal slash commands that
  Claude Code executes when invoked from any project. They drive Plane
  via MCP, manage git worktrees, run preview processes, handle the
  ticket lifecycle, and orchestrate parallel work via `/ticket-chain`
  and `/op-run`.
- **Coordination contract.** A small set of files
  (`.claude/plane-config.md`, `.claude/ticket-config.md`, `CLAUDE.md`,
  `.gitignore` with `.worktrees/`) is the workspace-side contract that
  every worker command reads. The TravelAgent extension and the
  `/ticket-install` command both write to this contract; the
  relationship is documented in
  [06-extension-and-external-contracts.md](06-extension-and-external-contracts.md).

## Where it sits in the three-tier stack

```
┌──────────────────────────────────────────────────────────────────┐
│  Producer:  throughline-interview-v2  (typed-state extraction)   │
│  Output:    typed_state.json + workflow doc + Plane fulfillments │
└──────────────────────────────────────────────────────────────────┘
                              │
                  HTTP (interview.throughlinetech.net)
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  Broker:    TravelAgent VS Code extension  (extension/)          │
│  Reads:     typed_state.json from Throughline                    │
│  Writes:    Plane work items via REST                            │
│  Drives:    /ticket-* commands by spawning terminals or          │
│             chat sessions (extension/src/actions/ticketActions)  │
└──────────────────────────────────────────────────────────────────┘
                              │
                  spawns `claude /ticket-chain SMOKE-1 SMOKE-2 ...`
                  or types into chat panel
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  Worker:    Claude Code CLI session  (this repo)                 │
│  Reads:     ~/.claude/commands/ticket-*.md (symlinked here)      │
│             .claude/plane-config.md, .claude/ticket-config.md    │
│  Writes:    git commits, Plane work items via MCP, .worktrees/   │
│  Reports:   prowl notifications, console output, Plane comments  │
└──────────────────────────────────────────────────────────────────┘
```

This doc set covers only the worker tier. The producer and broker tiers
are documented in their own state-of-the-system sets.

## Repo layout (file:line origins)

Top-level directories
(`README.md` lines 128–209 names them; what's actually on disk):

| Path | Role | Status |
|---|---|---|
| [commands/](../../commands/) | Universal Claude Code slash commands. 40 `.md` files. | Functional |
| [archive-commands/](../../archive-commands/) | Pre-Plane originals of every ticket-* command. Cited verbatim by the abbreviated current versions. | Legacy reference |
| [agents/](../../agents/) | User-level subagent definitions. `operation-worker.md` (real); `operation-task-lead.md` and `operation-conductor.md` (reference bodies — see status legend). | Mixed (one Functional, two Aspirational) |
| [bin/](../../bin/) | Cross-machine helper scripts (intercom, sync). Symlinked into `~/bin/`. | Functional |
| [hooks/](../../hooks/) | UserPromptSubmit hook (`surface-intercom-replies.sh`). | Functional |
| [extension/](../../extension/) | TravelAgent VS Code extension — separate codebase that lives in this repo. Compiled at install time when `node_modules/` exists. | Functional (see set 2) |
| [brief-templates/](../../brief-templates/) | Cross-model delegation brief templates. | Functional |
| [operation-templates/](../../operation-templates/) | One file: `META_PROMPT_FOR_PLAN_OPUS.md`. Copy-paste artefact for an external Opus session. | Functional |
| [copilot-prompts/](../../copilot-prompts/) | Mirrors of every Claude command for VS Code Copilot. Generated by `bin/sync-copilot-prompts`. | Functional |
| [plans/](../../plans/) | Synced plan inbox — write on one machine, execute on another. Symlinked to `~/.claude/plans/`. | Functional |
| [secrets/](../../secrets/) | Local-only `secrets/.env` with `PLANE_BASE_URL`, `PLANE_API_KEY`, `PLANE_WORKSPACE_SLUG`. Gitignored. | Functional |
| [docs/](../../docs/) | Architecture documentation (00–10 numbered) + `intercom-runbook.md` + `archive/`. | Functional reference |
| [windows/](../../windows/) | Task Scheduler XML template + render output for the intercom inbox listener. | Functional |
| [settings.{base,mac,windows}.json](../../settings.base.json) | Layered Claude Code permissions. `install.sh:181-186` merges base + platform into `~/.claude/settings.json` via `jq`. | Functional |

Three top-level prose files are part of the contract that propagates to
every machine:

- [CLAUDE.md](../../CLAUDE.md) — global instructions for every agent
  session (Prowl API key, `--prowl` opt-in flag, ticket commit-message
  format, "tickets are the system of record"). Symlinked to
  `~/.claude/CLAUDE.md`.
- [plan-mode.md](../../plan-mode.md) — discipline that fires when an
  agent enters plan mode (every `/ticket-investigate` cites it at line
  34).
- [brainstorm-mode.md](../../brainstorm-mode.md) — discipline that fires
  when `/brainstorm` runs (the command cites it at line 12).

## Status legend

Used to mark every command and every major code path:

- **Functional** — the body executes end-to-end as written. The user
  exercises this code path; it produces the output the body promises.
- **Partial** — the body executes but only covers a subset of cases the
  description suggests; gaps exist that the body acknowledges (often as
  "see archive for the full spec" or as a TODO).
- **Legacy** — the body still works but is being kept only until a
  named migration completes. New projects should not exercise this
  path. Markdown-backend halves of every ticket-* command are the
  largest example (Plan 3 will remove them).
- **Aspirational** — the body is written but is known not to run at
  all in the current harness. The two non-leaf operation agents are
  the canonical example: their frontmatter declares an `Agent` tool
  they cannot actually invoke (`commands/op-run.md:7-8` documents the
  harness limitation explicitly).
- **Broken** — the body executes but produces wrong output, or has
  observable bugs the maintainer has not addressed. None of the
  command bodies are currently classified as Broken; specific
  fragility notes live in the per-command sections.

## What you'll find in each doc

1. [01-installation-and-host.md](01-installation-and-host.md) — `install.sh`,
   `preflight.sh`, settings layering, secrets, Plane MCP registration,
   intercom subsystem, smoke tests, host requirements.
2. [02-ticket-install-and-workspace-contract.md](02-ticket-install-and-workspace-contract.md)
   — `/ticket-install`, the on-disk schemas (`plane-config.md`,
   `ticket-config.md`), the relationship to TravelAgent's stub-mode
   write of `plane-config.md`, and the on-disk contract every other
   ticket-* command reads.
3. [03-ticket-lifecycle-commands.md](03-ticket-lifecycle-commands.md)
   — the per-ticket commands: `/ticket-new`, `/ticket-investigate`,
   `/ticket-approve`, `/ticket-review`, `/ticket-preview`,
   `/ticket-ship`, `/ticket-defer`, `/ticket-close`, `/ticket-reopen`,
   `/ticket-cleanup`, `/ticket-list`, `/ticket-status`,
   `/ticket-promote`, `/ticket-delegate`, `/ticket-collect`. Their
   inputs, MCP tools, side effects, state transitions.
4. [04-ticket-orchestration.md](04-ticket-orchestration.md) — the
   parallel-execution commands: `/ticket-chain` (waves, dependency
   detection, preview, review checklist), `/ticket-batch` (parallel
   worktrees), `/op-scaffold` + `/op-run` (multi-plan operations).
   Worktree protocol, preview process state, residuals.
5. [05-non-ticket-commands.md](05-non-ticket-commands.md) —
   `/brainstorm`, `/plan-new`, `/plan-verify`, `/op-scaffold`, `/op-run`
   (overlap with set 4 deliberate; the operation surface is so big it
   needs its own section), and the intercom commands `/register`,
   `/send`, `/draft`, `/machines`, `/repos`.
6. [06-extension-and-external-contracts.md](06-extension-and-external-contracts.md)
   — what claude-config reads/writes from `<workspace>/.claude/*` that
   TravelAgent also touches; what the extension does at install time
   (writes a stub `plane-config.md` via `bindProject` — `extension/src/api/planeClient.ts:222-231`);
   what claude-config does NOT do (no fulfillment POST back to
   throughline-v2 — that is named in throughline-v2's contract as a
   future-agent surface and is unimplemented here);
   how claude-config's MCP requirements compose with the broker's REST
   client.
7. [07-operator-guide.md](07-operator-guide.md) — host install walkthrough
   (Mac/Linux/Windows), new-machine checklist, edit-sync matrix, maintenance
   cadence, intercom ops reference.
8. [08-troubleshooting-and-faq.md](08-troubleshooting-and-faq.md) —
   symptom-based troubleshooting (install, Claude Code, Copilot, plan handoff,
   settings, intercom) and FAQ (general, installation, daily use, delegation,
   secrets, sync, advanced).
9. [09-design-decisions.md](09-design-decisions.md) — the reasoning behind each
   non-obvious choice: brief-based delegation, platform-split settings,
   git-synced plans, wipe-and-regenerate settings, symlinks over copies,
   preflight separation, per-project tickets, effortLevel max.
## Loose ends (overview)

- **Three "ticket workflows" coexist in this one repo's history.** A
  Markdown era (still archived in [archive-commands/](../../archive-commands/)),
  a Plane era (the current shipped workflow), and an operation era
  (a separate orchestration surface for multi-plan refactors,
  documented under [04-ticket-orchestration.md](04-ticket-orchestration.md)).
  All three are documented as live; none of the three knows about the
  others' state machines. The three are reconciled only inside the
  human reading them.
