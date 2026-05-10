# 05 — Non-Ticket Commands

Everything in `commands/` that isn't a ticket-* lifecycle command.
Three families:

1. **Brainstorm + plan** — capture-side commands that produce ticket
   stubs and plan tickets.
2. **Operations** — covered in [04-ticket-orchestration.md](04-ticket-orchestration.md);
   only mentioned here for completeness.
3. **Intercom** — cross-machine messaging via MQTT.

## /brainstorm

**Status:** Functional (Markdown), Aspirational for Plane (the body
explicitly assumes `tickets/stub/` and a markdown ticket prefix; no
Plane path).

Body: [commands/brainstorm.md](../../commands/brainstorm.md). 73 lines.

### Inputs

- Optional topic argument (free text). If absent, ask the user "what
  do you want to brainstorm?".
- `--prowl` to send a notification at session end.

### Pre-flight (line 22)

Reads `.claude/ticket-config.md` for ticket prefix, zero-padding
width, and tickets directory. If missing, halts with "run
`/ticket-install`."

Notes the path `{tickets-dir}/stub/`. Created **at session-end**, not
at start.

### Discipline

The command's body is mostly a pointer to
[`~/.claude/brainstorm-mode.md`](../../brainstorm-mode.md), which
governs the session. Core rules quoted into the command body (lines
26–34):

1. **Default to capture, not convergence.** Every new topic is a
   candidate ticket.
2. **Maintain a running candidate-ticket list** inline. Show when
   asked or every ~10 exchanges.
3. **Propose splits** when a candidate grows wide. Default is split.
4. **Triage external feedback** (Gemini/Codex pastes): new ticket /
   modify existing / follow-up epic.
5. **No code, no plans.** Filenames + one-sentence descriptions max.
6. **Do not declare the session done** — wait for the user's signal.

### On stop signal (line 37)

When the user signals output ("produce the tickets," "ship it," or
similar):

1. Compute next IDs by scanning `{tickets-dir}/*.md` AND subdirs
   (`stub/`, `shipped/`, `deferred/`, `wontfix/`) — never reuse IDs.
2. Write epic file `{tickets-dir}/stub/EPIC-<slug>.md` with
   frontmatter (`status: stub`), north star, out of scope, member
   ticket list. Per template in `brainstorm-mode.md`.
3. Write ticket stubs: `{tickets-dir}/stub/TKT-NNN.md` per candidate,
   with frontmatter (`status: stub`, `epic: EPIC-<slug>`,
   `depends_on: [...]`), summary, acceptance criteria, notes.
4. **Write all files in one pass** before any commits land — so
   parallel sessions don't collide on IDs.

### Composition

Output drains via `/ticket-promote TKT-NNN [...]` — the human gate
documented at [03-ticket-lifecycle-commands.md](03-ticket-lifecycle-commands.md#ticket-promote).
Promoted stubs become `open` tickets and are then ready for
`/ticket-investigate`.

### Loose ends

- No Plane path. The Plane equivalent for "brain dump → many
  tickets" is `/plan-new` (next section), but that produces a plan
  ticket + children rather than stubs. The two surfaces are different
  shapes.
- The "compute next IDs" scan does NOT account for IDs that other
  parallel agents have reserved between the scan and the write. The
  "one pass before commits" rule (line 43) is the mitigation, but it
  doesn't prevent two `/brainstorm` sessions running concurrently
  from racing.

---

## /plan-new

**Status:** Functional, Plane-only.

Body: [commands/plan-new.md](../../commands/plan-new.md). 108 lines.

### Inputs

- `"<brain dump>"` inline argument (any length). OR
- `--from-file <path>` to read from disk.

If neither, error.

Plane-only (line 14): `/brainstorm` covers the Markdown stub case; no
ports.

### Steps (lines 26–98)

1. Read brain dump.
2. Read context: `plane-config.md`, `ticket-config.md`, `CLAUDE.md`,
   top context docs.
3. **Extract three things** from the dump:
   - **Guiding principles** (line 36) — invariants every child
     ticket should respect. 2–6 typical; >10 is a sign the plan is
     too broad.
   - **Candidate work items** (line 38) — bounded units of work.
     3–12 typical; >15 means break into two plans.
   - **Open questions** (line 40) — what the dump didn't answer.
   **Separation discipline is load-bearing** (line 43): principles
   in plan-ticket description; candidates as child tickets; questions
   as a comment. Don't conflate — `/plan-verify` parses these later.
4. **Create plan ticket** (line 46) via `mcp__plane__create_work_item`:
   - state Backlog
   - priority `medium`
   - description_html with `<h3>Guiding principles</h3>` + a footer
     paragraph documenting the contract
   - **labels = `[plan-ticket]`** — the load-bearing label
5. Post open questions as a comment (line 62) via
   `mcp__plane__create_work_item_comment`.
6. **Create each candidate child** (line 73) via
   `mcp__plane__create_work_item` with `parent` set to the plan
   ticket's UUID. Description uses the same template as
   `/ticket-new`. Do NOT auto-apply `risk:*` (that's
   `/ticket-investigate`'s call). Do NOT apply `stub` (line 80) —
   `/plan-new` is explicit-commitment; `/brainstorm` handles the
   stub case.
7. Output summary (line 83): plan ticket ID, principles count,
   children list, open questions count, next steps (review in Plane,
   prune children before investigating, then `/ti` or `/tch`).

### Rules (lines 102–107)

- Separation discipline is load-bearing — `/plan-verify` parses the
  plan ticket's description for principles.
- A plan ticket is **optional** — if the dump describes a single
  task, tell the user to use `/ticket-new` instead.
- If the dump is too ambiguous to extract 2+ principles and 3+
  candidates, STOP and ask for more detail. Don't fabricate.
- The plan ticket is **not a new primitive**. It's a regular work
  item that happens to carry the `plan-ticket` label.

### Composition

Children of a plan ticket are read by `/ticket-investigate` as
**read-only framing context** (commands/ticket-investigate.md:67-71)
— sub-tickets must not investigate siblings or expand scope. The
parent's principles are extracted as scoping context for each child's
implementation plan.

`/plan-verify <plan-ticket ID>` is the audit pass —
[commands/plan-verify.md](../../commands/plan-verify.md), 104 lines.
Plane-only.

### Loose ends

- The "2–6 principles" / "3–12 candidates" thresholds are LLM-driven
  judgments. There's no machine validation that a plan ticket exceeds
  the threshold; only the agent's discretion.
- Open-questions comment is a one-shot — re-running `/plan-new` on a
  refined dump does not reconcile against existing children. The user
  manually prunes.
- Plan tickets do not get a `risk:*` label even though they are
  Backlog. `/ticket-investigate` running on the plan-ticket itself
  would be ambiguous — none of the commands have a "if labels include
  `plan-ticket`, fall through to a different path" guard.

---

## /plan-verify

**Status:** Functional, Plane-only.

Body: [commands/plan-verify.md](../../commands/plan-verify.md). 104 lines.

### Inputs

`{ID}` of the plan ticket (or bare number). Plane-only — line 16.

### Pre-flight checks (line 22)

1. Load `plane-config.md`.
2. Retrieve work item; 404 → error.
3. **Plan-ticket gate**: labels must include `plan-ticket`. If not,
   error: "use `/ticket-review` for regular tickets."
4. **Principles gate**: description must contain `<h3>Guiding
   principles</h3>` or similar.

### Phase 1: Gather (lines 28–37)

1. **Principles** — parse from `description_html`.
2. **Children** — `mcp__plane__list_work_items(project_id=X,
   per_page=100, fields="id,sequence_id,name,state,parent",
   expand="state")` paginated via `next_cursor`. Filter client-side
   on `parent` matching the plan ticket UUID. The `fields=` argument
   is load-bearing (line 32): each `description_html` /
   `description_stripped` field is 5–150 KB; a 100-item page is ~3 MB
   without `fields=`, ~50 KB with. The query only needs scalar
   fields plus `state` to identify Done children.
   For each Done child:
   - Retrieve PR links via `mcp__plane__list_work_item_links`.
3. **PR diffs** — fetch `{repo}/pulls/{n}.diff` from GitHub/Gitea via
   REST (best-effort). Falls back to `.patch` variant or skips with
   a note.

### Phase 2: Judge (line 39)

Per principle, four-state verdict:
- `upheld`
- `partially upheld`
- `violated`
- `insufficient evidence`

Per principle: evidence (file:line refs supporting the verdict, or
absence of them), counter-evidence (specific file + change that
appears to violate). `insufficient evidence` is a valid honest
verdict — line 47.

### Phase 3: Write back (line 51)

Single comment on plan ticket via `mcp__plane__create_work_item_comment`.
**One comment per run** — re-running appends a new comment, never
overwrites (line 74).

### Output

Summary: scope (Done vs in-flight), per-principle verdict counts,
overall recommendation. If any principle is `violated`, prowl
priority 1 (line 95).

### Rules

- Read-only on codebase. Only writes one comment to plan ticket.
- Only judges Done children. In-flight children noted in scope but
  not judged.
- If zero Done children, STOP — "nothing to verify". Don't post
  empty comment.
- `insufficient evidence` is valid; do not massage to `upheld`.
- Never auto-fix. Identify, don't remediate.

### Loose ends

- PR diff fetch is HTTP only. No GitHub API auth integration — relies
  on `.diff`/`.patch` URL endpoints being publicly accessible (or
  the agent's `WebFetch` permissions allowing the host). Private
  repos behind auth = the diff fetch silently fails per PR.
- "PR link" is whatever URL `/ticket-ship` posted via
  `create_work_item_link` (Phase 5 of ship). That's best-effort to
  begin with — if `/ticket-ship` couldn't derive a PR URL, the
  Done child has no link, and `/plan-verify` skips it.
- Scoring per principle is unstructured prose. The summary's
  count-by-verdict relies on the agent following the four-state
  enum exactly.

---

## /op-scaffold and /op-run

Covered in [04-ticket-orchestration.md](04-ticket-orchestration.md#op-scaffold-and-op-run-multi-plan-operations).

Briefly:
- `/op-scaffold` — Functional. Validates a master plan markdown,
  expands to `docs/operations/<slug>/` with per-plan + per-brief
  files, prepends operation-level commands to brief Verification
  blocks.
- `/op-run` — Functional in main session; the spawned `operation-worker`
  subagent is functional. The `operation-task-lead` and
  `operation-conductor` agents are Aspirational reference bodies
  cited via heading-anchor URLs but never invoked.

The two are user-driven only. TravelAgent's coordinator does not
launch them.

---

## Intercom subsystem

Five slash commands plus one hook + six bin/ helpers + one Windows
Task Scheduler XML, all coordinated through MQTT.

**Status:** Functional, but the runtime listener (Mac mini receiver)
lives in a separate repo `claude-intercom`. claude-config holds only
the dispatcher side.

### What it does

Any Claude Code session on any machine can dispatch a prompt to any
other machine via a shared MQTT broker. The remote machine runs
`claude -p` against one of its local repos, and the response surfaces
in the dispatcher's inbox via the `UserPromptSubmit` hook.

### /register, /send, /draft, /machines, /repos

| Command | Body (lines) | Helper invoked | Effect |
|---|---|---|---|
| `/register <machine> <repo>` | [commands/register.md](../../commands/register.md) (31) | `~/bin/intercom-session set` | Persists `TARGET_MACHINE` + `TARGET_REPO` to `~/.config/intercom/session` |
| `/send <message>` | [commands/send.md](../../commands/send.md) (29) | `~/bin/send-job` | MQTT publish to `jobs/<machine>/<repo>` topic with `{prompt, ts}` payload |
| `/draft <description>` | [commands/draft.md](../../commands/draft.md) (37) | (composes prompt; awaits `y`/`n`; then `~/bin/send-job`) | Two-message conversation: agent composes a self-contained prompt, user confirms before dispatch |
| `/machines` | [commands/machines.md](../../commands/machines.md) (10) | `~/bin/intercom-machines` | MQTT publish to `control/registry/query`, subscribe `registry/#` for ~2s, render table |
| `/repos <machine> [n]` | [commands/repos.md](../../commands/repos.md) (22) | `~/bin/intercom-repos <machine> [n]` | Query a remote receiver for git repos by mtime |

The five command bodies are all thin shells: they parse `$ARGUMENTS`,
invoke a `bin/` helper via Bash, and surface the helper's output to
the user. No MCP. No Plane interaction. No state in the workspace.

### Helpers (bin/)

| Helper | What it does |
|---|---|
| [bin/send-job](../../bin/send-job) | `mosquitto_pub -t jobs/{machine}/{repo} -m {jobJson}` |
| [bin/intercom-session](../../bin/intercom-session) | Manage `~/.config/intercom/session` (get/set/clear) |
| [bin/intercom-machines](../../bin/intercom-machines) | Two-second query/response on `control/registry/query` |
| [bin/intercom-repos](../../bin/intercom-repos) | Query a specific machine for repos |
| [bin/intercom-inbox-mutate](../../bin/intercom-inbox-mutate) | Auto-archive large replies (stdin filter; lives in the listener pipeline) |
| [bin/intercom-inbox-listener](../../bin/intercom-inbox-listener) | `mosquitto_sub` on `replies/#`, append parsed lines to `~/.local/state/intercom/inbox.jsonl` |

All sourced credentials at runtime via
`source "$HOME/.config/intercom/creds"` — chmod 600 file with
`MQTT_HOST=`, `MQTT_PORT=`, `MQTT_USER=`, `MQTT_PASS=` lines. Written
by `install.sh:336-364` interactively (not committed).

### Reply surfacing

[hooks/surface-intercom-replies.sh](../../hooks/surface-intercom-replies.sh).
57 lines. Symlinked into `~/.claude/hooks/surface-intercom-replies.sh`
by `install.sh:323` and registered as a `UserPromptSubmit` hook in
`settings.base.json:62-71`.

Mechanism (file is annotated with the rationale):
- Append-only file at `~/.local/state/intercom/inbox.jsonl` (one JSON
  line per reply).
- Byte-offset cursor at `~/.local/state/intercom/inbox.cursor`.
- Each invocation reads from cursor to EOF, one line at a time.
- For each line: `jq -c .` parses; on success, surface the reply via
  a `[intercom replies — you MUST surface these…]` system message and
  advance the cursor by the line's byte length.
- On parse failure (torn / incomplete line): break, leave cursor
  unchanged. Listener finishes flushing; next hook invocation
  re-reads.

The surface message is intentionally bossy ("you MUST surface these
to the user at the top of your response") — the hook output becomes
part of the system context for the next user prompt.

### Cross-machine flow

```
machine A (dispatcher)                         machine B (receiver)
  │                                              │
  /register macmini foo-repo                     │
  /draft "fix the auth redirect"                 │
   ↓ user confirms                               │
  ~/bin/send-job → mosquitto_pub                 │
   topic: jobs/macmini/foo-repo                  │
   payload: {"prompt":"...","ts":...}            │
                                                 ▼
                                       mosquitto_sub on jobs/macmini/+
                                       runs `claude -p <prompt>`
                                       in foo-repo
                                                 │
                                       publishes to replies/macmini/foo-repo
   ↓
  ~/bin/intercom-inbox-listener (Task Scheduler / launchd)
   subscribes to replies/#
   appends to ~/.local/state/intercom/inbox.jsonl
   ↓
  next user prompt at machine A:
  surface-intercom-replies.sh fires (UserPromptSubmit hook)
   reads new bytes since last cursor
   prints `[intercom replies — you MUST surface these to the user…]`
   advances cursor
```

### Loose ends

- The runtime receiver (the Mac-side daemon listening on
  `jobs/<machine>/<repo>`) lives in a separate repo,
  `claude-intercom`. claude-config has no `bin/` for the receiver.
  README.md line 124 points users to
  `claude-intercom/docs/dogfooding-guide.md` for day-to-day usage.
- `/draft` is a two-message conversation. The first `/draft` call
  composes the prompt and stops; the next user message is the
  confirmation (`y`/`yes`/`ok`/`send` to dispatch; `n`/`no`/`cancel`
  to stop; anything else re-asks). This works only if the user's
  next message is genuinely a confirmation; ambiguous replies
  (e.g. "actually try this instead") re-enter step 3 with new
  guidance. Works in practice; brittle in concept.
- The hook fires on every `UserPromptSubmit`. There is no rate
  limit. A burst of replies would each push a system message into
  the agent's next response.
- The cursor file is plain text; corruption would silently lose
  replies (the cursor would advance past unread data) or repeat them
  (cursor stuck at zero re-reads everything). No checksum, no
  monotonicity check.
- `intercom-inbox-mutate` (auto-archive large replies) is referenced
  but its trigger surface isn't documented in the command bodies —
  it's a stdin filter that the listener pipeline composes itself.
  Loose end: where it sits in the pipeline isn't surfaced from
  claude-config.

---

## bin/ helpers (other)

Six are intercom helpers (above). The remaining three:

| Helper | Purpose | Status |
|---|---|---|
| [bin/claude-handoff](../../bin/claude-handoff) | Ship the most recent plan from `plans/` to the other machine | Functional |
| [bin/sync-repos](../../bin/sync-repos) | Pull latest on all repos (cross-machine sync) | Functional |
| [bin/sync-copilot-prompts](../../bin/sync-copilot-prompts) | Regenerate Copilot prompt mirrors from canonical Claude commands | Functional |
| [bin/migrate-markdown-to-plane](../../bin/migrate-markdown-to-plane) | Migrate a Markdown-backed project's `tickets/` into Plane work items | Aspirational (referenced in commit messages but not from any command body) |

`claude-handoff` and `sync-repos` are paired with the cross-machine
plans-syncing pattern documented in `docs/00-overview.md`. They run
outside Claude sessions (shell-only) and are exposed on PATH via
`install.sh:286-294`.

`sync-copilot-prompts` runs at install time
(`install.sh:228-235`) and on demand when commands change. Per
[memory note](../../../memory/MEMORY.md): "Claude owns
copilot-prompts/; run sync-claude-command after shipping command
changes (not at install time)." There's a tension between the
auto-run at install time and the memory's instruction to run it on
ship — the install-time run regenerates from whatever is committed,
which is correct.

`migrate-markdown-to-plane` is on disk but not referenced from any
command body. Per
[02-ticket-install-and-workspace-contract.md](02-ticket-install-and-workspace-contract.md#loose-ends),
it would be the consumer of the "Plan 3 will import them" promise in
`/ticket-install` Phase P8. As of HEAD, no command invokes it; user
runs it manually.

## Loose ends (this section)

- `/brainstorm` is Markdown-only. `/plan-new` is Plane-only. The two
  produce different artifacts (stub tickets vs plan-ticket +
  children). For a Plane project that wants a stub-style brain dump,
  there's no equivalent — the user creates `Backlog`-state work items
  manually with the `stub` label and parent. The capture surface is
  asymmetric across backends.
- `/plan-verify` doesn't loop into anything. Its output is one
  comment on the plan ticket; no follow-up command consumes it.
- The intercom commands have **no Plane involvement** — they're a
  parallel orchestration surface that doesn't intersect with the
  ticket workflow. There's no `/intercom-status` reading Plane state,
  no `/send` that posts to a Plane comment.
- `bin/migrate-markdown-to-plane` is the "Plan 3" migrator implied by
  multiple command bodies but disconnected from those commands. The
  user would run it manually, then re-run `/ticket-install` to
  switch backends.
