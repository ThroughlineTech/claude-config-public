# Overview: what this is, why it exists, and the mental model

## What it is, in one sentence

A git repo at `~/src/claude-config` that gives every coding agent on every machine a shared source of truth for instructions, commands, workflows, and settings — so you set things up once and every tool on every machine inherits it automatically.

## The problem it solves

Before this existed, the situation was:

1. **Claude Code accumulated configuration per machine.** Every new `xcodebuild` variant required a fresh permission grant. The Mac's `settings.json` had 200+ one-shot allow grants; Windows had 150+; none of it was portable.
2. **Copilot Chat had no shared context with Claude Code.** If you told Claude Code "use conventional commits" in a project, Copilot in that same project had no idea.
3. **Every project had its own ticket workflow, or none at all.** If you liked the ticket system you built in one project, you had to copy commands into every other project manually and adapt them per stack.
4. **Plans built on one machine didn't transfer.** You'd design something on the laptop in the evening and want to execute it on the always-on desktop the next morning, but the plan file lived only on the laptop.
5. **There was no pattern for using the best model per task.** If Gemini was better at UI work and Claude was better at architecture, there was no clean way to mix them — you picked one tool and hoped it was good at everything.
6. **Onboarding a new machine was hours.** A new laptop meant manually re-configuring Claude Code, VS Code, Copilot, your ticket workflow, your global conventions.

This repo fixes all six problems with one architectural move: **treat the agent-workflow layer as infrastructure, and put it in a git repo**.

## The mental model

Think of it in three layers:

```
┌─────────────────────────────────────────────────────────────┐
│  LAYER 3: The tools you use                                 │
│  Claude Code (CLI) + Copilot Chat (VS Code, any model)      │
└─────────────────────────────────────────────────────────────┘
                          ↑ both tools read from ↑
┌─────────────────────────────────────────────────────────────┐
│  LAYER 2: ~/.claude/ on each machine                        │
│  Contains symlinks into the claude-config repo, plus        │
│  a regenerated settings.json specific to the platform       │
└─────────────────────────────────────────────────────────────┘
                          ↑ symlinked into ↑
┌─────────────────────────────────────────────────────────────┐
│  LAYER 1: ~/src/claude-config/ (this repo, git)             │
│  Source of truth. Edit here, commit, push, pull elsewhere.  │
│  CLAUDE.md, commands/, brief-templates/, plans/, settings   │
└─────────────────────────────────────────────────────────────┘
```

Every machine has Layer 1 (the repo, via `git clone`) and Layer 2 (pointed at Layer 1, via `install.sh`). Layer 3 is whatever coding agents you have installed; they read from Layer 2 without knowing Layer 1 exists.

**Editing rule**: you always edit files in Layer 1. Layer 2 is read-only from your perspective (it's symlinks or regenerated files). Layer 3 is untouched.

## The key design decisions at a glance

Five choices that define the whole system. Each has a dedicated section in [10-design-decisions.md](10-design-decisions.md) if you want the full reasoning.

1. **Symlinks, not copies.** `install.sh` symlinks the repo's files into `~/.claude/`. This means editing a file in the repo (Layer 1) immediately changes what Claude Code sees (Layer 2) — no "sync" step required within a machine. The only sync is git push/pull between machines.

2. **One `CLAUDE.md`, two tools.** Claude Code reads `~/.claude/CLAUDE.md` directly (symlinked from the repo). Copilot reads a generated `claude-global.instructions.md` in VS Code's user prompts directory (also generated from the same `CLAUDE.md` and symlinked). Both tools get the same content from the same source.

3. **Ticket briefs as the cross-model contract.** Instead of making Claude Code directly call Gemini (impossible through Copilot), we use a self-contained markdown brief as the handoff format. Any model in any tool can read and execute a brief. This makes the delegation system model-agnostic and future-proof.

4. **Platform-split settings with jq merge.** Universal settings live in `settings.base.json`; Mac-specific in `settings.mac.json`; Windows-specific in `settings.windows.json`. `install.sh` merges base + platform into `~/.claude/settings.json` on each machine. No absolute paths in the synced files, no platform-specific junk in the universal file.

5. **Plans live in the repo.** The `plans/` directory is synced like everything else. Write a plan on one machine, `claude-handoff` pushes it, `git pull` on the other machine surfaces it. Plans become a durable, searchable, cross-machine artifact instead of ephemeral local state.

## What this repo is NOT

- **Not a Claude Code replacement or alternative.** It's a config layer on top of Claude Code.
- **Not a hosted service.** Everything runs locally. The only network calls are git push/pull and whatever the agents themselves do.
- **Not an auto-orchestration framework.** There's no background process watching for events. You drive it: you run commands, you read the output, you decide what's next. The tooling reduces the friction of each step.
- **Not magic.** If you strip it all away, what's left is: a markdown file with instructions, a directory of markdown prompt files, a JSON file with settings, and a bash script to symlink them. The "magic" is that this handful of files is syncable and reusable across tools and machines.

## Who maintains this

You do. There's no upstream, no package to update, no release schedule. When you want it to do something new, you add a file or edit an existing one, commit, push, and run `install.sh` on each machine. See [07-editing-and-syncing.md](07-editing-and-syncing.md) for the workflow and [11-maintenance.md](11-maintenance.md) for the cadence to keep it healthy.

## Where to go next

- **Set up the repo on a new machine**: [01-install.md](01-install.md) (detailed walkthrough) or [06-adding-a-new-machine.md](06-adding-a-new-machine.md) (quick checklist)
- **Use the ticket workflow**: [02-ticket-workflow.md](02-ticket-workflow.md)
- **Understand the cross-model delegation**: [03-delegation.md](03-delegation.md)
- **Understand the plumbing**: [04-architecture.md](04-architecture.md)
