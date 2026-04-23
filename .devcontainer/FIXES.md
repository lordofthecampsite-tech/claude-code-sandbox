# Dev Container Fixes

A running log of problems encountered in Claude Code devcontainers and their resolved fixes. Drop this file into a new repo's `.devcontainer/` directory when bootstrapping; point Claude at it when symptoms match. Each entry is self-contained: symptom, diagnosis, root cause, fix, verification.

Append new entries as they come up. Don't delete old ones even if they're obsoleted by template changes — the diagnosis/root-cause context is useful.

## Contents

1. [UTF-8 / locale — garbled output, `setlocale` warnings](#1-utf-8--locale)
2. [Container → Mac-host service via `host.docker.internal` — "No route to host"](#2-container--mac-host-via-hostdockerinternal)
3. [`bash cat < /dev/tcp/…` false timeouts on client-speaks-first protocols](#3-bash-cat--devtcp-false-timeouts)

---

## 1. UTF-8 / locale

### Symptom

- Every command prints a warning: `bash: warning: setlocale: LC_ALL: cannot change locale (en_US.UTF-8)`.
- UTF-8 characters (em-dashes, box-drawing, checkmarks, arrows) render as mojibake, or their column widths are miscounted so adjacent styled spans overlap and whole words appear to vanish.
- TUI tools (`htop`, `ncdu`, Python `rich` output) misalign columns.

### Diagnosis

Run inside the container:

```bash
echo "LANG=$LANG LC_ALL=$LC_ALL"
locale -a | grep -E "en_US|UTF"
locale
```

Confirming signals:

- `LANG` and/or `LC_ALL` are set to `en_US.UTF-8` (or another locale that isn't `C.utf8`).
- `locale -a` does NOT list `en_US.utf8` — the only UTF-8 entry is `C.utf8`.
- `locale` prints `Cannot set LC_CTYPE to default locale: No such file or directory` for each LC_* variable.

### Root cause

The Debian base image in Anthropic's Claude Code devcontainer template only generates the `C.UTF-8` locale. The `zsh-in-docker` tool used to install oh-my-zsh hardcodes three lines at the top of `~/.zshrc`:

```
export LANG='en_US.UTF-8'
export LANGUAGE='en_US:en'
export LC_ALL='en_US.UTF-8'
```

Those exports override anything set via `containerEnv` / `/etc/environment`. glibc can't find the requested locale, silently falls back to `C` (7-bit ASCII) semantics, and `wcwidth(3)` returns -1 for any non-ASCII codepoint. Every program that computes visible column widths (ncurses, readline, Python rich, agent output with tables) miscounts and the terminal cursor lands in the wrong column.

### Fix (two edits)

**Edit 1 — `.devcontainer/devcontainer.json`**, inside `containerEnv`:

```json
"containerEnv": {
    // ... existing keys ...
    "LANG": "C.UTF-8",
    "LC_ALL": "C.UTF-8"
}
```

This populates `/etc/environment` with the locale that's actually installed.

**Edit 2 — `.devcontainer/Dockerfile`**, a new `RUN` layer right AFTER the `zsh-in-docker` install block:

```dockerfile
# zsh-in-docker injects `export LANG='en_US.UTF-8'` (+ LC_ALL, LANGUAGE) at
# the top of ~/.zshrc, but the Debian base image only generates C.UTF-8 —
# so glibc errors on every command and UTF-8 widths miscompute. Strip those
# lines so containerEnv's LANG=C.UTF-8 in /etc/environment stays authoritative.
RUN sed -i -E "/^export (LANG|LC_ALL|LANGUAGE)=.*en_US/d" /home/node/.zshrc
```

Adjust `/home/node/.zshrc` if the non-root user in your devcontainer is not `node`.

### Verify

Rebuild the container (VS Code → *Dev Containers: Rebuild Container*), open a fresh terminal, and run:

```bash
echo "LANG=$LANG LC_ALL=$LC_ALL"
locale
```

Expected: `LANG=C.UTF-8` and `LC_ALL=C.UTF-8`. `locale` should print values without any `Cannot set LC_CTYPE` errors.

### Why C.UTF-8 instead of generating en_US.UTF-8

`C.UTF-8` ships with glibc on every Debian/Ubuntu image — no `apt install`, no `locale-gen`, no extra Dockerfile layer. For English workflows it's functionally equivalent to `en_US.UTF-8` minus regional formatting (date format, currency symbol, decimal separator). If you genuinely need `en_US.UTF-8` for locale-sensitive output, the alternative is:

```dockerfile
RUN apt-get update && apt-get install -y locales && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen
```

Then use `LANG=en_US.UTF-8` in `containerEnv` instead of `C.UTF-8`. Both fix the symptom; `C.UTF-8` is simpler.

---

## 2. Container → Mac-host via `host.docker.internal`

### Symptom

- From inside the container, connecting to a service running on the Mac host via `host.docker.internal:<port>` fails with `No route to host` (fast) or `Network is unreachable` (fast).
- DNS resolution for `host.docker.internal` works (`getent hosts host.docker.internal` returns an IP, typically `192.168.65.254` on Docker Desktop for Mac).
- The service on the Mac is confirmed running and reachable from the Mac itself (`nc -z 127.0.0.1 <port>` succeeds on the Mac).

### Diagnosis

```bash
# Resolution works?
getent hosts host.docker.internal
# Expect: 192.168.65.254  host.docker.internal  (Docker Desktop for Mac)

# Routing says…
ip route
# Expect: default via 172.17.0.1 dev eth0   and   172.17.0.0/16 dev eth0 …

# Firewall state (template installs init-firewall.sh with default-DROP OUTPUT)
sudo iptables -L OUTPUT -n | head -20
# Look for an ACCEPT rule covering 192.168.65.254. If only 172.17.0.0/24 is
# accepted, the host-gateway IP is not covered — fix is needed.

# Confirm the symptom is iptables reject (not a stopped service on the Mac):
# "No route to host" = ICMP admin-prohibited from the container's own iptables.
# "Connection refused" = service on Mac is down (different problem).
```

### Root cause

Docker Desktop for Mac routes container traffic through vpnkit, which puts the Mac host on a separate /24 (`192.168.65.0/24`, with the host at `.254`) from the container's bridge network (`172.17.0.0/24`). The devcontainer template's `init-firewall.sh` derives `HOST_NETWORK` from the *default route gateway*:

```bash
HOST_IP=$(ip route | awk '/default/ {print $3; exit}')
HOST_NETWORK=$(echo "$HOST_IP" | sed 's|\.[0-9]*$|.0/24|')
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
```

That derives `172.17.0.0/24` — the bridge subnet — which does NOT include `192.168.65.254`. The default-DROP OUTPUT policy (with an explicit REJECT at the end) rejects the container's connection to the host-gateway IP before it ever leaves.

Separately: `--add-host=host.docker.internal:host-gateway` in `devcontainer.json` `runArgs` injects both A and AAAA records into `/etc/hosts`. The container usually has no IPv6 default route, so bash `/dev/tcp/host.docker.internal/…` resolves v6 first, errors with `Network is unreachable` before trying v4, and masks the actual problem.

### Fix

**Edit 1 — `.devcontainer/devcontainer.json`**, add to `runArgs` (if not already there):

```json
"runArgs": [
    "--cap-add=NET_ADMIN",
    "--cap-add=NET_RAW",
    "--add-host=host.docker.internal:host-gateway"
]
```

**Edit 2 — `.devcontainer/init-firewall.sh`**, add a new block right after the existing `HOST_NETWORK` ACCEPT rule:

```bash
# Docker Desktop host-gateway (host.docker.internal — service on the Mac).
# Docker Desktop puts the host on a separate /24 from the bridge default
# route, so HOST_NETWORK above doesn't cover it. Resolve at firewall-start
# time since the IP varies by Docker Desktop version.
HOST_GATEWAY_IP=$(getent ahostsv4 host.docker.internal | awk 'NR==1{print $1}')
if [ -n "$HOST_GATEWAY_IP" ]; then
    echo "Host gateway (host.docker.internal): $HOST_GATEWAY_IP"
    iptables -A OUTPUT -d "$HOST_GATEWAY_IP" -j ACCEPT
    iptables -A INPUT  -s "$HOST_GATEWAY_IP" -j ACCEPT
fi
```

`getent ahostsv4` returns IPv4 only, sidestepping the IPv6 `/etc/hosts` record. Resolving at firewall-start time makes the rule robust to Docker Desktop version drift (the host-gateway IP can change across upgrades).

### Verify

Rebuild the container so `/usr/local/bin/init-firewall.sh` is re-baked from the patched source (the Dockerfile `COPY` pulls it in at build time; `postStartCommand` runs it on every start).

Then inside the container:

```bash
# Firewall rule installed?
sudo iptables -L OUTPUT -n | grep 192.168.65
# Expect: ACCEPT  0  --  0.0.0.0/0  192.168.65.254

# TCP reachability to the Mac service? Use the actual protocol client —
# NOT `cat < /dev/tcp/…` (see entry #3 below for why).
# Example with nc -z (connect-only probe):
nc -z -w3 192.168.65.254 <port>; echo exit=$?
# exit=0 → reached. exit≠0 with "connection refused" → service on Mac is down
# (not a firewall problem). Silent timeout → something on the Mac is silently
# dropping (macOS Application Firewall, or service bound to loopback with
# vpnkit unable to forward).
```

### Related gotcha: vpnkit NATs the source IP to 127.0.0.1

When the container connects through `host.docker.internal`, Docker Desktop's vpnkit rewrites the source IP so the Mac service sees the connection as coming from `127.0.0.1` (loopback), NOT from the container's bridge IP (`172.17.0.x`). Any Mac service with a trusted-source-IP whitelist should:

- Treat `127.0.0.1` as the permitted source, OR
- Disable the source check entirely for local dev.

In particular: **Interactive Brokers Gateway's "Trusted IPs" should contain `127.0.0.1` (or the check should be off), not the container's bridge IP**. I spent real time adding `172.17.0.2` to Trusted IPs, which was completely inert — vpnkit rewrites the source before Gateway ever sees the SYN.

### Related gotcha: Java servers binding IPv6-only

macOS Java servers (IB Gateway, Tomcat, etc.) often show up in `lsof` as `IPv6 … TCP *:port (LISTEN)`. The `IPv6` family label looks like it means "v4 won't work," but by default `IPV6_V6ONLY=false` on macOS so the socket is dual-stack — v4 connections are accepted as v4-mapped-v6. **Do not add `-Djava.net.preferIPv4Stack=true` to vmoptions unless you've actually tested that `nc -4 -z 127.0.0.1 <port>` from the Mac fails.** If the v4 `nc` succeeds locally, the v6-only theory is wrong; the timeout is somewhere else.

---

## 3. `bash cat < /dev/tcp/…` false timeouts

### Symptom

Using `timeout N bash -c 'cat < /dev/tcp/host/port'` to probe TCP reachability returns `exit=124` (timeout) even when the service is running and the connection is actually established.

### Diagnosis

Watch the TCP handshake from the server side:

```bash
# On the server host:
sudo tcpdump -n -i lo0 'tcp port <port>' -c 4
```

If tcpdump shows a full 3-way handshake (`S`, `S.`, `.`) between the probe and the server, the TCP layer is fine — the timeout is misleading.

### Root cause

`cat < /dev/tcp/host/port` opens the TCP connection, then `cat` blocks reading. For **client-speaks-first protocols** (IB Gateway API, some databases, some RPC frameworks), the server doesn't emit any bytes until the client sends an identifier or handshake string. `cat` pushes nothing, the server sits silently waiting, bash's `timeout` kills `cat` after N seconds. The TCP connection worked perfectly; the tool was the wrong one.

### Fix (use the right tool)

For pure TCP reachability:

```bash
nc -z -w3 <host> <port>; echo exit=$?
# exit=0 → connect succeeded. exit≠0 → genuine failure.
```

For protocol-level verification, run the actual client:

```bash
# Example: IB Gateway
python -c "from ib_insync import IB; ib=IB(); \
    ib.connect('host', 4002, clientId=1, timeout=8, readonly=True); \
    print(ib.client.serverVersion()); ib.disconnect()"
```

The `nc -z` probe is my default for container-to-host connectivity checks — don't reach for `/dev/tcp` unless you need to actually push bytes into the stream.
