---
description: Audits the sandbox for drift, leaked secrets, and common foot-guns. Safe to run anytime.
---

# /sandbox-check — sanity audit of this sandbox

Audit the current sandbox configuration and report findings. Do NOT modify any files during this audit — just report. If the user wants a fix applied, they'll ask.

Cover these four areas in order. For each, produce a short "OK" or "FINDING" per item.

## 1. Secrets hygiene

- `git check-ignore -v .claude/settings.local.json` — must report it's ignored.
- `git check-ignore -v .env .env.local` — same.
- `git check-ignore -v HANDOFF.md` — same.
- Grep the tracked-files tree (not `.git`, not `node_modules`, not `.session-archive`) for obvious secret patterns: `sk_live_`, `sk_test_`, `sbp_` (Supabase PAT prefix), `ghp_`, `github_pat_`, `gho_`, `AKIA` (AWS), `xoxb-` (Slack bot). Any hit is a FINDING regardless of whether it's in a gitignored file — plaintext on disk is a finding.
- Grep `.claude/settings.local.json` for the pattern `export .*=` — hardcoded tokens in permission allowlists are a common foot-gun because it traps the secret in plaintext on disk even though the file is gitignored.

## 2. Firewall allowlist drift

- Read `.devcontainer/init-firewall.sh`, extract `ALLOWED_DOMAINS`.
- Check what tracked code actually reaches out to (grep for `http` URLs in source, `fetch(` calls, hardcoded hostnames in config files). Flag any domain used in code but not in the allowlist (the container would be silently broken for that call).
- Flag any domain in the allowlist that appears in NO tracked code (stale entry; safe to remove).
- Report the current `LAN_NETWORK` setting if uncommented, and whether the user's stated LAN subnet still matches (ask if uncertain).

## 3. HANDOFF + memory freshness

- `stat` HANDOFF.md mtime. If >7 days old, FINDING (memory is drifting from reality).
- If HANDOFF.md contains "Next Step" with an exact command, and the repo state contradicts it (e.g. it says "commit v0.3.5" but HEAD is already on v0.3.5), FINDING.
- Check `memory/MEMORY.md` for entries whose named target files don't exist, or that reference branches/commits no longer in `git log`. FINDING per broken pointer.

## 4. Dockerfile + devcontainer coherence

- If Dockerfile installs a toolchain (Python, Go, Rust, Arduino), devcontainer.json should have a matching cache volume. Flag missing.
- If devcontainer.json has a cache volume mount, the Dockerfile or postCreateCommand should install the tool that uses it. Flag orphan mounts.
- If the Dockerfile has an `Example:` block uncommented but the firewall's corresponding service domains aren't in the allowlist, FINDING (toolchain installed but can't download anything).

## Report format

Emit a single message, grouped by section, each line one of:

- `✓ OK:` (followed by the thing that was checked and passed)
- `⚠ FINDING:` (followed by what's wrong AND a concrete suggested fix line the user could paste back as an instruction)

End with a one-line summary: `N OK / M findings`. If 0 findings, say "Sandbox looks clean."

## Rules

- Read-only. Don't edit files. Don't commit. Don't push.
- Don't print secret values in the report, even if you found one — say "hardcoded token in `<file>`, line `<n>`" and stop.
- If the user asks you to fix a specific finding, THEN you can edit — but that's a separate ask.
