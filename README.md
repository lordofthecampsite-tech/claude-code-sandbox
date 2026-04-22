# Claude Code Sandbox

A dev-container template for using [Claude Code](https://docs.claude.com/claude-code) on real work. Gives you:

- A **sandboxed container** — Node 20 + zsh + Claude Code preinstalled, nothing project-specific.
- A **DNS-first firewall** — default-deny with an allowlist of only what Claude Code itself needs. Extending to your services is a one-line edit.
- **Session-durability hooks** — your work survives context compaction, session loss, and days between sittings. A `HANDOFF.md` ratchet forces a resume-ready snapshot every time you stop.
- A **file-based memory system** — cross-session knowledge about you, your project, and rules of engagement. Claude keeps it current.
- Two **onboarding commands** — `/setup` configures the sandbox for your specific project; `/sandbox-check` audits it for drift and leaks.

Everything is text files. No hidden magic. You can read and edit any of it.

---

## Why it's shaped this way

**Sandboxed because LLMs have unbounded reach.** A naive Claude Code setup runs with your user's full filesystem and network access. Mostly fine; occasionally terrifying. The container isolates filesystem (via workspace bind-mount) and network (via firewall) to the explicit set you approve.

**DNS-first firewall instead of a proxy.** A dnsmasq process on 127.0.0.1 resolves only allowed hostnames; iptables drops everything else. Hardcoded-IP exfil attempts are blocked for free because they never appear in the ipset. Extending is a one-line edit to `ALLOWED_DOMAINS` — no TLS interception, no per-app config.

**`HANDOFF.md` enforced by a Stop hook because context loss is the #1 productivity killer in long sessions.** Claude Code compacts, sessions crash, laptops close. Without a snapshot, a week of work evaporates into a hazy summary. The Stop hook blocks session end if `HANDOFF.md` is stale, forcing you to leave behind a doc that a cold reader (you, next week) can resume from.

**File-based memory instead of in-context memorization.** Claude forgets between sessions; you don't want to re-teach "I'm a backend engineer, I prefer small PRs, we're migrating auth this quarter" every morning. The `memory/` directory holds that knowledge as markdown files Claude loads on demand.

**Scripts directory instead of pasted command sequences.** Multi-step host operations get wrapped. You will not remember the exact command order in three months. The script will.

---

## 5-minute quickstart

Pick whichever host you're using — the template works identically on all three.

### Option A: GitHub (fastest if your project is also on GitHub)
```bash
gh repo create my-project --template <owner>/claude-code-sandbox --private --clone
cd my-project
```
Or click the green "Use this template" button on the repo page.

### Option B: BitBucket (web-only, no CLI)
In BitBucket: **Create** → **Repository** → scroll to "Import repository" → paste `https://github.com/<owner>/claude-code-sandbox`. Name it, set private, go. Then clone the new BB repo locally.

### Option C: Any git host (GitLab, Gitea, self-hosted, BitBucket, GitHub)
```bash
git clone https://github.com/<owner>/claude-code-sandbox my-project
cd my-project
rm -rf .git && git init -b main
git add . && git commit -m "Initial from claude-code-sandbox template"
# Create an empty repo in your host's UI, copy the HTTPS URL, then:
git remote add origin <your-repo-url>
git push -u origin main
```

### After you have the repo locally

```bash
# Open the project folder in VS Code, then "Reopen in Container"
# (requires the Dev Containers extension). First build: ~3 min.
# Firewall comes up automatically on start.

# In a container terminal:
claude           # launches Claude Code

# Inside Claude Code:
/setup           # wizard: 6 questions, configures firewall + Dockerfile + CLAUDE.md
```

That's it. You're working inside a sandbox configured for your project.

---

## What's in this template

```
claude-code-sandbox/
├── .devcontainer/
│   ├── Dockerfile                 # Node 20 + firewall toolchain + Claude Code
│   ├── devcontainer.json          # VS Code dev-container definition
│   └── init-firewall.sh           # DNS-first iptables allowlist
├── .claude/
│   ├── settings.json              # Three hooks (see below)
│   └── commands/
│       ├── setup.md               # /setup — onboarding wizard
│       └── sandbox-check.md       # /sandbox-check — drift + leak audit
├── memory/
│   └── README.md                  # Empty by default; explains the memory model
├── scripts/
│   └── README.md                  # Wrap-in-scripts convention
├── CLAUDE.md                      # Placeholder until /setup runs
├── HANDOFF.md.template            # 5-section skeleton for session snapshots
├── .gitignore                     # Sensible defaults (secrets, sessions, build noise)
└── README.md                      # This file
```

---

## The three hooks, explained

In `.claude/settings.json`:

### 1. `Stop` → HANDOFF ratchet
Every time a session tries to end (user types `exit`, Claude finishes a turn with no follow-up, etc.), a shell command checks `HANDOFF.md`. If it's older than 30 minutes, the hook blocks session end with a message: *"Write or update HANDOFF.md before stopping."* The block can only be cleared by Claude writing the file.

Effect: you always leave a session with a resume-ready doc. Not a log — a snapshot. Overwritten each time.

### 2. `Stop` → session archive
Copies the raw Claude Code session JSONL into `.session-archive/` (gitignored). Full-fidelity history if you ever need to replay a conversation.

### 3. `PreCompact` → refresh HANDOFF before summarization
When Claude is about to auto-compact a long conversation, this hook runs an agent that reads the live transcript and rewrites `HANDOFF.md` with maximum fidelity BEFORE the compactor throws detail away. Prevents the classic "wait, I lost the important bit" when context gets summarized.

Delete any of the three if you don't want them. I strongly suggest keeping the HANDOFF ratchet — it's the single most load-bearing habit in this template.

---

## HANDOFF.md vs `claude --resume` vs `claude --continue`

Three tools, three jobs. They're complementary, not competing. Most people learning Claude Code find out about `--continue` / `--resume` later than they should — worth knowing all three up front.

| You just... | Use | Why |
|---|---|---|
| ...**crashed** — terminal died, VS Code closed mid-session, container rebuilt, Mac decided to reboot | `claude --continue` | Reloads the most recent conversation in this project at full fidelity. Fastest crash recovery — no state lost that Claude Code still has on disk. |
| ...want to jump back into a **specific earlier thread** from a previous day (e.g. "continue the auth refactor, not the migration one") | `claude --resume` | Picks from a list of past sessions. Useful when you've had multiple parallel threads in the same project. |
| ...are **returning after an evening, a weekend, or several days**, OR working **from a different machine** | Read `HANDOFF.md` first, then start fresh | HANDOFF is a 200-line curated snapshot of where things stand. Cheaper and clearer to re-enter from than rehydrating an hours-old conversation, and it works on any machine — `--resume` only works where the original session's JSONL lives. |

**Why HANDOFF doesn't go away just because `--resume` exists:**

- **Compaction eats detail.** Long sessions auto-compact, which summarizes early turns. `--resume` on a compacted session loads the *summary*, not the raw turns — the detail is permanently gone. The PreCompact hook in this template writes HANDOFF *before* the compactor runs, so the critical state survives.
- **Machine-portable.** HANDOFF can live in the repo (it's gitignored by default — one line to change if you want it committed); `--resume` only works on the machine where the conversation happened.
- **Humans read it too.** HANDOFF is a resume-ready doc for a teammate, a code-review reader, or future-you. `--resume` is Claude-readable only.
- **Curation removes mess.** If a previous session went sideways, `--resume` reloads the confused state. HANDOFF is your curated correction — "here's where things actually ended up."

**Rule of thumb:** `--continue` for same-day recovery. HANDOFF for anything with a meaningful gap or a move to a new machine. `--resume` when you specifically want to rehydrate an older thread rather than the most recent.

---

## Extending the firewall

Add a hostname to `ALLOWED_DOMAINS` in `.devcontainer/init-firewall.sh`:

```bash
ALLOWED_DOMAINS=(
    # ... existing ...
    api.stripe.com        # added: payments
    myapp.vercel.app      # added: deploy target
)
```

Rebuild or re-run: `sudo /usr/local/bin/init-firewall.sh`.

dnsmasq handles subdomains automatically — `supabase.co` covers `*.supabase.co`. No wildcard needed.

---

## Extending the toolchain

Two places to add install steps:

1. **`.devcontainer/Dockerfile`** — runs at image build time. Use for tools that rarely change version (arduino-cli, Python, Go, Rust). Cached across container rebuilds.

2. **`devcontainer.json` `postCreateCommand`** — runs on first container create. Use for tools that go into a mounted named volume (Arduino ESP32 core, Go module cache, Rust cargo registry). Keeps image size down.

Both files have commented `// Example:` sections showing real invocations for the common toolchains. Uncomment what you need, or let `/setup` do it from your answers.

---

## Extending the memory

Don't pre-write anything. Memories accumulate organically:

- You correct Claude's approach → Claude writes `memory/feedback_<topic>.md`.
- You describe the project's history → Claude writes `memory/project_<topic>.md`.
- You mention where bug tickets live → Claude writes `memory/reference_<system>.md`.

See `memory/README.md` for the frontmatter format and the four memory types.

---

## Security notes

- **`.claude/settings.local.json` is gitignored**, but it's still plaintext on disk. The Bash permission allowlist has historically been a place people paste `export TOKEN=<value>` entries — don't. Any token pasted there stays in cleartext on the filesystem indefinitely.
- **`HANDOFF.md` is gitignored**. If you keep secrets-as-context in there, they stay local but they stay plaintext.
- **Use `.env` + `.env.example` for anything secret at runtime.** Both patterns are gitignored; `.env.example` documents the shape.
- **`/sandbox-check` runs a leak-pattern grep** over the tracked tree. Useful before each push.

---

## License

MIT. See [LICENSE](LICENSE).

---

## Credits

This template was extracted from a long-running [off-grid power management project](https://github.com/lordofthecampsite-tech/CabinPowerController) where Claude Code was used extensively across dozens of sessions, often days apart. The patterns here — HANDOFF ratchet, DNS-first firewall, memory system — emerged from what actually kept that project's state coherent across gaps. Borrow what's useful; delete what isn't.
