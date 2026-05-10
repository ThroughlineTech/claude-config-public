## Stage 1: Merge PR #1 and land it on both machines



```
# Locally (Windows):
gh pr merge 1 --merge       # or --squash, your preference

# On Mac:
cd ~/src/claude-config && git checkout main && git pull
./install.sh                # refreshes symlinks + re-syncs Copilot mirrors

# On Laptop (same):
cd ~/src/claude-config && git checkout main && git pull
./install.sh
```

After this, both machines have the new `/ticket-*` Plane-path behavior and the auto-link spec. The already-migrated projects (throughline-site, rejog-ios) will lazy-migrate their `plane-config.md` on first `/ticket-list` per machine — one-time transparent upgrade.

## Stage 2: Migrate each remaining project

Per-project procedure (for projects #3–#8 per the handoff doc's migration order):



```
# On Mac, from the project's repo root, fresh Claude Code session:

# 1. Pre-flight — clean tree, no live worktrees
git status && git fetch --all
ls .worktrees/ticket-* 2>/dev/null   # must be empty; ship or abandon first

# 2. Bootstrap Plane project (~5 min, interactive AskUserQuestion batch)
/ticket-install

# 3. Import the markdown tickets (~1-10 min depending on count)
./bin/migrate-markdown-to-plane --dry-run    # classification check
./bin/migrate-markdown-to-plane              # real run, foreground

# 4. Smoke test
/ticket-list                                 # should open Active view URL
/ticket-status <some imported TKT>           # should show lifecycle

# 5. Cut over
git checkout -b feat/migrate-to-plane
git rm -rf tickets/
git add .claude/plane-config.md .claude/ticket-config.md CLAUDE.md .gitignore
git commit -m "migrate: cut over to Plane-backed ticketing"
gh pr create --title "Migrate to Plane-backed ticketing" --body "Plan 3 migration."
```

Merge the PR after a quick review (or self-merge for solo projects). That repo is now on Plane.

**Order from the handoff doc:**

| #    | Project                  | Notes                                                |
| ---- | ------------------------ | ---------------------------------------------------- |
| 3    | `claude-config`          | Dogfooding — the tooling repo now uses the tooling   |
| 4    | `codenoscopy`            | Check for in-flight cost-optimization work           |
| 5    | `loomwork`               | Framework — no in-flight changes blocking downstream |
| 6    | `sidefire` / `sidefire2` | Sidefire2 is the active one                          |
| 7    | `johnny-solarseed`       | Vitest suite survives migration (no Plane touch)     |
| 8    | `openbaseline`           | If active work exists; otherwise fresh Plane project |

## Stage 3: Sync each migrated project to the Laptop

After you merge a project's migration PR on the Mac, pull on the Laptop:



```
# On Laptop, per project:
cd ~/src/<project>
git checkout main && git pull
# First /ticket-list on the Laptop may lazy-cache view URLs into
# plane-config.md (same one-time write as Stage 1). Commit that if it
# appears as uncommitted, or ignore — it's idempotent either way.
```

The per-project `.claude/plane-config.md` + `.claude/ticket-config.md` travel with the repo via git, so the Laptop automatically gets the config once you pull. The Laptop's MCP credentials are already set up from Stage 1's `install.sh` run.

## Stage 4: Final verification across everything

When all 6 remaining projects are migrated:

-  Every project's `git log main` shows a "migrate: cut over to Plane-backed ticketing" commit.
-  Every project's `tickets/` directory is gone.
-  `/ticket-list` in each project opens a Plane URL (no markdown path taken).
-  Configure a workspace-level view in Plane: "Active across all projects" — the single-pane-of-glass that was the whole point of the migration (Plan 3 cross-project-concerns section).

## Sequencing recommendations

**Don't batch the migrations.** Plan 3 procedure is explicit: after each project, pause, check it feels right before moving to the next. Especially critical:

- **Project 3 (`claude-config` itself)** — dogfooding. If the migration tool can't migrate its own home, something's wrong.
- **Project 6 (`sidefire2`)** — Cloudflare Workers preview profile is unusual; if the preview infrastructure breaks, catch it here before #7 and #8.

**Give yourself a day or two between projects** to let any weirdness surface in normal use.

**If anything feels worse than the old system at any point**, stop, note what specifically is worse, and decide: fix in the tooling before resuming, or roll back that project. Plan 3's rollback is mechanical (revert the PR, `tickets/` reappears from git history).