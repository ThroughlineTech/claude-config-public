# claude-config

Personal dotfiles + universal workflow for **Claude Code** and **GitHub Copilot Chat**. One place to store the instructions, slash commands, brief templates, and settings that every coding agent on every machine should use.

## What is this, in one paragraph

A git repo that lives at `~/src/claude-config` on every machine. An installer (`install.sh`) symlinks the repo's contents into `~/.claude/` and into VS Code's Copilot prompts directory. After installation, **both Claude Code and Copilot Chat automatically share a single source of truth** for: your global instructions (how you want agents to behave), a universal ticket workflow (ten slash commands available in every project), a cross-model delegation system (hand any ticket phase to any model via a markdown brief), and a curated permission baseline for Claude Code. Edit once, commit, push, pull on the other machine, and every tool on every machine picks up the change.

## Who this is for

- **You, in 6 months**, when you've forgotten why half of this exists
- **You, setting up a new machine**, who wants to be productive in under 5 minutes
- **A collaborator you add to the repo**, who needs to understand the workflow without a conversation with you

## Quickstart (new machine)

```bash
# 1. Clone
git clone git@github.com:<you>/claude-config.git ~/src/claude-config
cd ~/src/claude-config

# 2. Preflight (read-only safety check — mutates nothing)
bash preflight.sh

# 3. If preflight reports 0 failures, install
bash install.sh

# 4. Pick up the new PATH
source ~/.bashrc   # or ~/.zshrc on Mac

# 5. Smoke test
# In a new VS Code Copilot Chat: "send me a test prowl"
# If a notification arrives on your phone, everything works.
```

See **[docs/01-install.md](docs/01-install.md)** for the detailed walkthrough including Windows-specific gotchas.

## The most common things you'll do

Daily work happens mostly through the ticket workflow. In any project that has been bootstrapped with `/ticket-install`:

| Command | When to use it |
|---|---|
| `/ticket-new "short description"` | Start tracking a new bug, feature, or enhancement |
| `/ticket-list` | "Where am I? What's in flight?" |
| `/ticket-investigate TKT-001` | Have Claude Code explore the codebase and write a plan |
| `/ticket-approve TKT-001` | Branch + implement the plan (Claude Code does the work) |
| `/ticket-delegate TKT-001 implement` | Hand the implementation to Gemini or another model via Copilot Chat |
| `/ticket-collect TKT-001` | After a delegation returns, pull the work back into the Claude Code flow |
| `/ticket-review TKT-001` | Generate a human verification checklist |
| `/ticket-ship TKT-001` | Rebase, run tests, merge, (optionally) deploy |
| `/ticket-status TKT-001` | "What happened to this ticket? What's the next step?" |

See **[docs/02-ticket-workflow.md](docs/02-ticket-workflow.md)** for the full lifecycle and examples, or **[docs/05-commands-reference.md](docs/05-commands-reference.md)** for a terse one-section-per-command reference.

## The interesting trick: cross-model delegation

You can hand any ticket phase (investigate, implement, review) or a peer review of any phase to a different model — Gemini, GPT, Claude, whatever — via a self-contained markdown brief. The brief format is the contract; any model that can read markdown and execute code can take it from there.

Common pattern:

```
Claude Code investigates → Gemini peer-reviews the investigation →
Claude Code revises → Claude Code implements →
Gemini peer-reviews the diff → Claude Code ships
```

See **[docs/03-delegation.md](docs/03-delegation.md)** for how this works, why it's designed this way, and how to use it.

## What's in the repo

```
claude-config/
  README.md                          ← this file
  CLAUDE.md                          ← global instructions (Prowl, conventions) — single source of truth
  install.sh                         ← idempotent installer
  preflight.sh                       ← read-only pre-install safety check
  CHANGELOG.md                       ← human-readable log of significant changes

  commands/                          ← Claude Code universal slash commands
    README.md
    ticket-install.md  ticket-new.md  ticket-list.md
    ticket-investigate.md  ticket-approve.md  ticket-review.md  ticket-ship.md
    ticket-delegate.md  ticket-collect.md  ticket-status.md

  brief-templates/                   ← templates for cross-model delegation briefs
    README.md
    investigate.md  implement.md  review.md
    verify-investigate.md  verify-implement.md  verify-review.md

  copilot-prompts/
    run-brief.prompt.md              ← Copilot prompt: execute any delegation brief
    claude-global.instructions.md    ← generated from CLAUDE.md, symlinked into VS Code

  plans/                             ← synced plan inbox (write on one machine, execute on another)

  bin/
    claude-handoff                   ← ship the most recent plan to the other machine

  settings.base.json                 ← universal Claude Code settings (allows, denies, env)
  settings.mac.json                  ← Mac-only settings additions
  settings.windows.json              ← Windows-only settings additions

  docs/
    00-overview.md                   ← what this is, why it exists, mental model
    01-install.md                    ← detailed install walkthrough
    02-ticket-workflow.md            ← ticket lifecycle in detail
    03-delegation.md                 ← cross-model delegation pattern
    04-architecture.md               ← how the pieces fit together
    05-commands-reference.md         ← one section per command
    06-adding-a-new-machine.md       ← "I got a new laptop" procedure
    07-editing-and-syncing.md        ← how to change things and propagate
    08-troubleshooting.md            ← real failure modes we hit + fixes
    09-faq.md                        ← questions you will ask in the future
    10-design-decisions.md           ← the "why this way" for non-obvious choices
    11-maintenance.md                ← ops cadence: what to do weekly/monthly/per-machine
```

## Documentation map

Start with **[docs/00-overview.md](docs/00-overview.md)** if you've never seen this repo before.

| I want to… | Read |
|---|---|
| Understand what this thing is and why it exists | [00-overview.md](docs/00-overview.md) |
| Set up this on a new machine | [01-install.md](docs/01-install.md) and [06-adding-a-new-machine.md](docs/06-adding-a-new-machine.md) |
| Use the ticket workflow on a real project | [02-ticket-workflow.md](docs/02-ticket-workflow.md) |
| Delegate work to a different model | [03-delegation.md](docs/03-delegation.md) |
| Understand how it's all wired together | [04-architecture.md](docs/04-architecture.md) |
| Look up a command quickly | [05-commands-reference.md](docs/05-commands-reference.md) |
| Edit something and propagate the change | [07-editing-and-syncing.md](docs/07-editing-and-syncing.md) |
| Fix something that broke | [08-troubleshooting.md](docs/08-troubleshooting.md) |
| Find the answer to "how do I…?" | [09-faq.md](docs/09-faq.md) |
| Understand *why* it's designed this way | [10-design-decisions.md](docs/10-design-decisions.md) |
| Keep the repo healthy over time | [11-maintenance.md](docs/11-maintenance.md) |

## Public template — this is a fork-and-customize starter

This is the public template version of `claude-config`. It contains the workflow infrastructure (commands, brief templates, install scripts, settings baseline, docs) without any personal secrets, plans, or project-specific content.

**To use it:**

1. **Fork this repo** (or clone and re-init: `git clone <url> ~/src/claude-config && cd ~/src/claude-config && rm -rf .git && git init`)
2. **Customize `CLAUDE.md`** — it ships as a template with placeholders. Add your own push notification setup, your own conventions, anything else you want every agent to know
3. **Decide on visibility:**
   - If you put secrets directly in `CLAUDE.md` (an API key, etc.), **make your fork private**
   - If you want to keep your fork public, store secrets in `~/.claude/secrets.md` (already in `.gitignore`) and reference them from `CLAUDE.md` indirectly. See the `CLAUDE.md` template's "Where to put secrets" section.
4. **Run `bash install.sh`** to wire everything into `~/.claude/` and your VS Code Copilot prompts directory
5. **Use it.** Open a Claude Code session in any project and try `/ticket-install`, then `/ticket-new`. Try Copilot Chat with the global instructions loaded automatically.

## Platform support

| Platform | Supported | Notes |
|---|---|---|
| macOS | ✅ first-class | Default development target |
| Windows (Git Bash) | ✅ supported | Requires Developer Mode + `MSYS=winsymlinks:nativestrict` (handled automatically by install.sh) |
| Windows (WSL) | ✅ should work | Not the primary test environment |
| Linux | ✅ should work | Untested but the script handles it |
| Windows (PowerShell native) | ❌ not supported | Use Git Bash or WSL |

## License

MIT. See [LICENSE](LICENSE). Use, fork, modify, and redistribute freely. Attribution appreciated but not required.

## Credits

Originally extracted from a personal dotfiles project. The patterns (universal commands, cross-model delegation via briefs, three-layer architecture, jq settings merge, etc.) are documented exhaustively in [docs/10-design-decisions.md](docs/10-design-decisions.md) so you can understand the reasoning before forking.
