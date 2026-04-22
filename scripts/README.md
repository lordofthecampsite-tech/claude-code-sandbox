# scripts/

One-shot, single-purpose shell scripts for operations you invoke repeatedly from the host or from the container.

## The convention

When a task takes more than one command to execute on the host side — build something, upload something, reset a service, tail logs from multiple places — wrap it in a script here. Don't leave it as "just paste these three commands."

Reasons:

- **Ergonomics**: you may be on a laptop with no desk or mouse when the need comes up. One command is faster and less error-prone than three.
- **Reviewability**: Claude Code can read and edit the script; a pasted ad-hoc sequence disappears as soon as the terminal scrolls.
- **Reproducibility**: six months later, you will not remember the command order. The script will.

## Shape

- One script per task. Small is good. `scripts/deploy.sh`, `scripts/tail-logs.sh`, `scripts/reset-db.sh`.
- Start each script with a short header comment explaining what it does, how to invoke it, and what env vars it needs.
- Use `set -euo pipefail` so failures surface instead of compounding silently.
- Accept arguments positionally with simple usage messages (`${1:?Usage: $0 <version>}`) — Bash's `:?` default does most of the work.
- Prefer env-vars-via-prompt over hardcoded secrets. If a secret is needed, check it's set at the top and error out with instructions if not.

## Example skeleton

```bash
#!/usr/bin/env bash
#
# scripts/example.sh — <one-line description>
#
# Usage:   ./scripts/example.sh <arg1> [arg2]
# Env:     MY_TOKEN (required)

set -euo pipefail
IFS=$'\n\t'

ARG1="${1:?Usage: $0 <arg1> [arg2]}"
ARG2="${2:-default}"
: "${MY_TOKEN:?Set MY_TOKEN in your env}"

# ... the actual work ...
echo "Running with $ARG1 and $ARG2"
```

## Delete this README when you ship your first real script

Once `scripts/` has anything useful in it, this README has served its purpose — you can delete it or replace it with a project-specific index of what each script does.
