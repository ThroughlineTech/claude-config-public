---
description: TKT-XXX — launch a ticket preview without shipping
argument-hint: TKT-XXX
---

# Preview a Ticket

Build and launch an inspectable version of a ticket's feature branch **without** merging to main. This is how you smoke-test before shipping: localhost, staging, simulator, whatever the project defines as "preview."

## Input

Argument: `{ID}` (e.g. `TKT-014`)

## Pre-flight Checks

- `.claude/ticket-config.md` must exist. If not, tell the user to run `/ticket-install` and stop.
- Read `## Preview profiles`, `Preview mode`, and `Preview port base` from the config. If the profiles section is empty, STOP: "No preview profiles configured — run `/ticket-install` to set one up, or skip preview for this project."
- **Locate the ticket file** at `{tickets-dir}/{ID}.md` (active set). If it lives in a terminal subfolder, STOP and tell the user to `/ticket-reopen` first.
- Ticket must have a non-empty `branch` field. If not: "ticket has no branch — run `/ticket-approve` or `/ticket-delegate ... implement` first."
- Ticket status should be `in-progress`, `review`, or `delegated`. Reject `open`/`proposed` and terminal statuses.
- Read the ticket's `app:` field. If missing, fall back to the profile marked `default: true`. If `app: (none)`, STOP with "this ticket has no preview profile set — edit the ticket's `app:` field or run without preview."

## Steps

1. **Resolve the profile:**
   - Look up `app: {profile-name}` in the config's `## Preview profiles`.
   - If the profile is **atomic**, the component list is `[{profile}]`.
   - If the profile is **compound**, the component list is its `Components:` array.
   - Fail with a clear error if a referenced profile name doesn't exist in the config.

2. **Compute the port for each component:**
   - Extract the numeric part of the ticket ID (e.g. `TKT-014` → `14`).
   - For each component, `PORT = {Preview port base} + {numeric-id} + {component's Port offset}`. Example: TKT-014 with `server` (offset 0) → `3014`, `client` (offset 1000) → `4014`.
   - Build a map `{SERVER_PORT: 3014, CLIENT_PORT: 4014, ...}` (uppercase component name + `_PORT`) for cross-component substitution in step 4.

3. **Determine the working directory:**
   - If a worktree exists at `.worktrees/ticket-{lowercased-id}/`, use it.
   - Otherwise, use the repo root (checking out `{branch}` first; warn if the tree is dirty with unrelated changes, refuse if so).

4. **Launch components in dependency order:**
   - Build a dependency-ordered launch list from the components' `Depends on:` fields. Topological sort; error on cycles.
   - For each component in order:
     1. Substitute placeholders in its `Command`: `{PORT}` → this component's port, `{ID}`, `{BRANCH}`, `{WORKTREE}`, and any `{<OTHER>_PORT}` references from the map computed in step 2.
     2. Launch via Bash with `run_in_background: true`. Capture the PID.
     3. **Wait for readiness** per the component's `Ready when:` rule:
        - `http {path}` → poll `http://localhost:{PORT}{path}` up to 30s; any HTTP response counts as ready.
        - `log {pattern}` → tail the background process output for up to 30s looking for a regex match.
        - `delay {seconds}` → blind sleep.
        - `command-exit` → wait for the command to exit (used for build-and-install flows like Xcode; the "process" isn't persistent).
     4. If the component fails readiness (timeout, process died, etc.): kill any components already launched in this preview, clean up, and STOP with a clear error identifying which component failed.
   - Append one line per component to `.worktrees/ticket-{lowercased-id}/.preview.pid`:
     ```
     {component-name}  {pid}  {port}
     ```
     (One component per line. `pid` is `-` for `command-exit` components that don't leave a persistent process.)
   - Write a sidecar `.worktrees/ticket-{lowercased-id}/.preview.meta` recording: profile name, list of components + commands + URLs, started_at, branch. Used by `/ticket-cleanup` and `/ticket-status` to explain what's running.

5. **Notify the user** via the push-notification channel configured in `~/.claude/CLAUDE.md` (Prowl, Pushover, ntfy.sh, Slack webhook, etc. — whatever the user has set up). Skip silently if no channel is configured.
   - Title: `{ID} preview ready`
   - Body: compact summary of URLs/instructions. Single atomic: `http://localhost:3014`. Compound: `API :3014, Web :4014 — open http://localhost:4014 to test`. iOS: `simulator: {bundle-id} launched`. Compound with iOS: `Host running; iOS companion launched`.

## Finish

Output:

```
{ID} PREVIEW READY

Branch:   {branch}
Worktree: {path or "(repo root)"}
Preview:  {url or instruction}
PID:      {pid}

To stop this preview:   /ticket-cleanup {ID}
To ship:                /ticket-ship {ID}
To send it back:        describe the issue; it'll be fixed on the same branch
```

## Rules

- **Never run the preview command on `main`.** Always on the feature branch or its worktree. If you can't confirm you're on the feature branch, STOP.
- **One preview per ticket at a time.** Before launching, check `.worktrees/ticket-{lowercased-id}/.preview.pid`. If a PID is there and the process is still alive, skip re-launching and just report where it's already running.
- **Dirty working tree**: if we're running from the repo root (not a worktree) and there are unrelated uncommitted changes, REFUSE — ask the user to commit/stash first. In a worktree, the tree is dedicated to this ticket, so local changes there are fine.
- **Placeholder substitution is literal text replacement**, not shell expansion. If the user's preview command has `{PORT}` in it, that's what gets replaced. If it doesn't, the command runs as-is (and port binding is the project's problem).
- If the preview command errors or exits immediately, report the exit code and the last few lines of output — do not silently pretend it's running.
- Do NOT modify the ticket file, git state, or any code. Preview is read-only on the ticket.
