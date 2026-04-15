# Security Review — claude-config-public

**Date:** 2026-04-07
**Scope:** Full repo contents + git history (1 commit) for anything that shouldn't be in a public release.

## TL;DR

**Repo is safe to publish.** No secrets, credentials, tokens, private paths, personal email addresses, or identifying information were found in tracked files or in git history. The single commit is authored by an anonymized identity (`claude-config <noreply@example.com>`). The Prowl API key from your *private* global `~/.claude/CLAUDE.md` is **not** present in this repo — the tracked [CLAUDE.md](../CLAUDE.md) is the template version with `YOUR_PROWL_API_KEY_HERE` as the placeholder.

No action required before publishing. A few minor hardening suggestions below.

## What I checked

1. **Secret scan** — grepped tracked files for `api[_-]?key`, `apikey`, `secret`, `password`, `token`, `bearer`, PEM headers, `sk-…`, `ghp_…`, `xox[bp]-…`. All hits are documentation describing *how* to handle secrets, not actual secrets.
2. **Specific Prowl key** — grepped for the literal API key `d7a87a0d…` from your private global CLAUDE.md. **Not present.**
3. **Personal identifiers** — searched for your name, username (`fubar`), email patterns, absolute home paths. Findings are limited to:
   - [settings.windows.json:11](../settings.windows.json#L11) — `Read(/c/Users/**)` (generic glob, not personal)
   - [docs/01-install.md:51](docs/01-install.md#L51) — example path `/Users/you/...` (placeholder)
   - [preflight.sh:236-238](../preflight.sh#L236-L238) — reads `git config user.email` at runtime, doesn't hardcode it
4. **Git history** — only one commit (`0fe6883 Initial public release`). Author: `claude-config <noreply@example.com>` — already anonymized. No leaked history from your private repo.
5. **Shell scripts** ([install.sh](../install.sh), [preflight.sh](../preflight.sh), [bin/claude-handoff](../bin/claude-handoff)) — no `curl | sh`, no `eval`, no `wget`, no http:// fetches. Clean.
6. **Settings files** — no credentials in `permissions.allow`. The deny list correctly blocks `sudo`, `wget`, `chmod`, and `rm -rf` of root/home.
7. **.gitignore** — properly excludes `secrets.md`, `.env`, `.env.*`, and the generated copilot prompts file.

## Findings

### None blocking.

### Minor / informational

1. **Permissive `Read(*)` / `Edit(*)` / `Write(*)` and `Bash(curl:*)` in [settings.base.json](../settings.base.json).** This is a deliberate design choice for a personal config (you want the agent to be powerful), but anyone copying this template inherits a very permissive baseline. Worth a sentence in the README pointing out that `curl:*` + `Write(*)` is effectively "the agent can download and write anything" and forks should tighten as needed. Not a leak — just a downstream-user awareness item.

2. **`Bash(git:*)` allows `git push`, `git reset --hard`, `git config`, etc.** with no confirmation. Same caveat as above — fine for you, worth flagging for forkers.

3. **Future-proofing:** consider adding a pre-commit hook or CI scan (gitleaks, trufflehog) so that if you later paste a real key into `CLAUDE.md` by accident, it gets caught before push. Your [docs/09-faq.md](09-faq.md) already explains the recovery procedure, but prevention is cheaper.

4. **Author identity hygiene.** The commit is anonymized to `noreply@example.com`, which is good. If you make further commits from this working tree, double-check `git config user.email` in this repo so you don't accidentally start attaching your real identity to public commits. A repo-local `git config user.email "<id>+<username>@users.noreply.github.com"` would lock this in.

## Verdict

Ship it. The template is doing exactly what it claims: workflow infrastructure with no personal data and no secrets. Your private `~/.claude/CLAUDE.md` (with the real Prowl key) lives outside this repo and was correctly excluded.

---

## Amendment — 2026-04-08 re-review

Re-ran the full sweep after the 0.2.0 work landed. One **action-required** finding this time.

### Repo state since the last review

- New commit on `main`, not yet pushed: `67f8c2f tickets: terminal folders, preview profiles, batch workflow (0.2.0)` — adds the batch/preview/cleanup/defer/close/reopen commands and surrounding docs (19 files, +905/-25).
- No new tracked files outside `commands/`, `docs/`, `CHANGELOG.md`, `README.md`.

### Re-scan results

1. **Secret scan** (re-run against current tree, including new commit): no API keys, tokens, PEM blocks, or provider-prefixed credentials. The only `apikey=` hit is still the `YOUR_PROWL_API_KEY_HERE` placeholder in [CLAUDE.md:28](../CLAUDE.md#L28).
2. **Personal identifier scan in tracked files**: clean. No occurrences of `fubar`, `Daniel Richardson`, `plymptonia`, `@yahoo`, or real home paths in any tracked file. Only [docs/01-install.md:51](01-install.md#L51) `/Users/you/...` placeholder, same as before.
3. **New commands review** ([commands/ticket-batch.md](../commands/ticket-batch.md), [ticket-cleanup.md](../commands/ticket-cleanup.md), [ticket-preview.md](../commands/ticket-preview.md), [ticket-defer.md](../commands/ticket-defer.md), [ticket-close.md](../commands/ticket-close.md), [ticket-reopen.md](../commands/ticket-reopen.md), updated [ticket-install.md](../commands/ticket-install.md)): generic workflow text. No hardcoded paths, hostnames, project names, machine names, or third-party identifiers tying back to your personal setup. The notification language was deliberately genericized in this release (per the commit body) and that holds up under inspection.
4. **Shell scripts**: unchanged since last review. Still no `curl | sh`, `eval`, or remote fetches.
5. **.gitignore / settings files**: unchanged.

### 🟡 Action required: commit 67f8c2f author identity leak

```
Author: Daniel Richardson <plymptonia@yahoo.com>
```

Commit `67f8c2f` is signed with your **real name and real personal email**, unlike the initial release commit `0fe6883` which used the anonymized `claude-config <noreply@example.com>`. If you push this branch as-is to a public remote, that name + email becomes permanently associated with the repo via `git log` and the GitHub commits API — even if you later rewrite history, mirrors and the GitHub events feed may have already captured it.

This was item #4 ("author identity hygiene") in the previous review's *informational* section. It is now **active** rather than hypothetical.

**Recommended fix before pushing:**

1. Set a repo-local anonymized identity so it can't recur:
   ```bash
   git -C c:/Users/fubar/src/claude-config-public config user.name  "claude-config"
   git -C c:/Users/fubar/src/claude-config-public config user.email "noreply@example.com"
   ```
   (Or use a GitHub `<id>+<username>@users.noreply.github.com` address if you'd rather the commits still attribute to your GitHub account without exposing your real email.)
2. Rewrite the offending commit's author. Since `67f8c2f` is the tip and not yet pushed, the simplest fix is:
   ```bash
   git commit --amend --reset-author --no-edit
   ```
   after step 1. Verify with `git log -1 --format='%an <%ae>'` before pushing.
3. If you've already pushed `67f8c2f` to the public remote by the time you read this, the email is effectively leaked — `plymptonia@yahoo.com` should be considered publicly associated with this repo regardless of any subsequent force-push, because GitHub's events API and third-party mirrors cache commit metadata. In that case the value of cleanup is preventing *future* exposure, not undoing the past one.

### Everything else

No other regressions. Repo is otherwise still clean and safe to publish once the author identity on `67f8c2f` is corrected.
