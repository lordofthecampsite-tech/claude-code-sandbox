# Welcome to this Claude Code Sandbox

**This sandbox has not been configured for a specific project yet.**

Run the `/setup` command to customize it. A five-question wizard will adapt the firewall allowlist, Dockerfile toolchain, devcontainer volumes, and this file to your project.

If you want to explore first, the key pieces to read are:

- `README.md` — the why of this template: container + firewall + Claude Code durability patterns.
- `.devcontainer/init-firewall.sh` — the DNS-first allowlist. Minimal by default.
- `.claude/settings.json` — session-durability hooks (HANDOFF ratchet, session archive, PreCompact refresh).
- `memory/README.md` — how the cross-session memory system works.

After `/setup` runs, this file gets replaced with a project-specific `CLAUDE.md` describing your project's conventions, gotchas, and constraints.
