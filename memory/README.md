# Memory

This directory is where Claude Code writes durable, file-based memories that persist across sessions. It's the other half of the session-durability story — `HANDOFF.md` captures *current-session* state, this directory captures *cross-session* knowledge about you, your work, and your feedback.

## The model

Each memory is a single markdown file with YAML frontmatter. `MEMORY.md` in this directory is a one-line-per-memory index that Claude loads at the start of every session — so keep it short (under ~150 lines total). Individual memory files are loaded on-demand when their description matches the current task.

## The four types

| Type       | When to write                                                                                                   | When to read                                        |
| ---------- | --------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| `user`     | You told Claude something about yourself — role, expertise, preferences, how you like to be communicated with.  | Whenever framing explanations or picking tradeoffs. |
| `feedback` | You corrected Claude, or Claude made a non-obvious choice that you confirmed. Records *rules of engagement*.    | Whenever the same situation recurs.                 |
| `project`  | Cross-session facts about the work: why an initiative exists, who's involved, deadlines, incident context.      | When the current task touches the initiative.       |
| `reference`| Pointers to external systems — Linear project IDs, Grafana dashboards, relevant Slack channels, docs URLs.      | When the user mentions the external system.         |

## What NOT to save

- Code patterns, conventions, architecture, file paths — derivable by reading the current project state.
- Git history or who-changed-what — `git log` / `git blame` are authoritative.
- Debugging solutions — the fix is in the code; the commit message has context.
- Ephemeral task state — that belongs in HANDOFF.md or task lists.
- Anything already in a `CLAUDE.md` file.

If Claude is about to save something that overlaps with one of those, it should update an *existing* memory instead of writing a new one.

## File format

```markdown
---
name: One-line title
description: A specific description — future-you needs to decide relevance at a glance
type: user | feedback | project | reference
---

(Memory body. For `feedback` and `project` types, structure as:)

The rule / fact itself, stated plainly.

**Why:** the reason this was recorded (often a past incident or the user's explicit preference).

**How to apply:** when the rule / fact should kick in.
```

## Index format (`MEMORY.md`)

One line per memory. Under ~150 chars each. Example:

```
- [User Profile](user_profile.md) — Alex, backend-heavy, new to Rust
- [Prefer small PRs](feedback_pr_size.md) — refactors in ≤200 LOC chunks, cite: 2025-11-03 review
- [Payments migration](project_payments_q1.md) — Stripe→Adyen by 2026-02-15, blocked on legal
```

## Growing the directory

Empty on purpose. `/setup` may seed a `user_profile.md` from the onboarding conversation. After that, memories accumulate organically — any time Claude learns something worth keeping, it writes a file and appends a line to `MEMORY.md`.

If this directory gets noisy or contradictory, ask Claude to prune it — it'll consolidate duplicates and delete stale entries.
