---
description: Onboarding wizard — configures this sandbox for a specific project by editing the firewall, Dockerfile, devcontainer.json, and CLAUDE.md.
---

# /setup — configure this sandbox for your project

You are helping the user customize the `claude-code-sandbox` template for their specific project. The template's default state is deliberately minimal — base firewall allows only what Claude Code itself needs, no language toolchain is preinstalled, CLAUDE.md is a placeholder. Your job is to turn that generic base into something useful for *this* user's *this* project.

## Flow

**Ask questions one at a time, waiting for the user's reply before moving to the next.** Do NOT dump all five questions at once — that produces shallow answers. Keep each question short.

1. "What are you building? One sentence is fine — a web app, a CLI, firmware for an ESP32, a data pipeline, etc."

2. "Where does it run in production? Vercel / Fly / AWS / Cloudflare / none / something else?"

3. "What backend services will you call? Databases, APIs, auth providers, payment, LLM providers. Name them; I'll translate to firewall domains."

4. "Which language toolchain(s) do you want preinstalled in the container? Node is already there. Python, Go, Rust, Arduino, or none-needed are the usual answers."

5. "Anything unusual about the network? The most common extra is 'yes, the container needs to reach $service-on-my-LAN at 192.168.x.x' — otherwise say no."

If the user is vague on any answer, ask a clarifying follow-up. Don't guess.

## After gathering answers

Propose a unified set of edits and show the user a diff **before making any changes**:

- **`.devcontainer/init-firewall.sh`**: append domains to `ALLOWED_DOMAINS` for the deploy target (Q2) and backend services (Q3). Use comments above the new entries grouping them by purpose. If Q5 mentioned a LAN, uncomment the `LAN_NETWORK` block near the bottom and set the subnet.

- **`.devcontainer/Dockerfile`**: if Q4 needs a toolchain, uncomment the matching "Example" section (or add a new install block if none match). Place it above the Claude Code install so cache-invalidation order stays reasonable.

- **`.devcontainer/devcontainer.json`**: if the toolchain from Q4 benefits from a cache volume (almost all do), uncomment the matching named-volume mount. Update `postCreateCommand` if bootstrap commands are needed (e.g. `pipx install poetry && poetry install`, `arduino-cli core install esp32:esp32`, `go mod download`).

- **`CLAUDE.md`**: replace the placeholder entirely. New content: a one-paragraph project description from Q1, a "Conventions" section (always bumps a version string, always wraps multi-step host commands in scripts/, etc — ask if any apply), a "Gotchas" section (only if the user surfaced any). Keep it under 30 lines; CLAUDE.md is loaded on every session so density matters.

- **`memory/`**: if the user mentioned anything about themselves during the conversation (role, experience, preferences), write `memory/user_profile.md` and add it to `memory/MEMORY.md` (create MEMORY.md if it doesn't exist). Use the frontmatter format from `memory/README.md`.

- **`scripts/`**: if the user mentions any multi-step host-side workflow (e.g. "I deploy by running `cargo build --release` then scp-ing the binary…"), offer to scaffold a `scripts/<name>.sh` for it.

Show the full diff, ask the user to confirm. Apply after confirmation.

## Last step: commit + optional push

After edits are applied and confirmed:

1. `git add -A && git commit -m "Configure sandbox for <project name from Q1>"`.

2. Check `gh auth status`. If the user is authenticated AND they want to push, run `gh repo create <name> --private --source=. --push`. Ask for the repo name; default to the parent directory name. If `gh auth status` fails, skip this step and tell the user "Run `gh auth login` then `gh repo create <name> --private --source=. --push` when ready."

## Rules

- Don't hallucinate service domains. If the user names a service you're not sure about (e.g. "Neon"), ask them to confirm the API hostname, or browse their docs to find it.
- Don't touch `.claude/settings.json`. The hooks ship as-is; if the user wants to customize hooks that's a separate `/add-hook` task we haven't built yet.
- If the user says "skip Q3, I don't have backend services yet" — skip the firewall edit for that question. Don't invent domains to fill.
- One commit at the end. Not per-file.
- Don't push without permission, even if `gh auth status` passes.
