#!/bin/bash
# init-firewall.sh — DNS-first network allowlist for the Claude Code sandbox.
#
# Model:
#   - dnsmasq runs on 127.0.0.1:53 as the container's ONLY DNS resolver.
#   - dnsmasq resolves allowed hostnames upstream and auto-populates an
#     iptables ipset with each resolved IP (per-query, so CDN IP rotation
#     is handled automatically).
#   - Everything else returns NXDOMAIN and is dropped.
#   - iptables OUTPUT defaults to DROP; only IPs in the ipset pass.
#   - Hardcoded IPs (no DNS lookup) are blocked because they aren't in the
#     ipset.
#
# Why DNS-first instead of a proxy: simpler, no per-app TLS interception,
# and catches direct-IP exfil attempts for free. The allowlist is the only
# knob you need.
#
# To allow a new service: add its hostname to ALLOWED_DOMAINS below and
# re-run this script (or rebuild the container). dnsmasq matches subdomains
# automatically, so `supabase.co` covers `*.supabase.co`.
#
# Common patterns in your ALLOWED_DOMAINS edits:
#   - Deploy targets: `vercel.com api.vercel.com <yourapp>.vercel.app`
#     (or fly.io, cloudflare.com, aws.amazon.com + specific region, etc.)
#   - Backend services: `supabase.co` (subdomains auto-matched), or more
#     specific like `api.stripe.com`, `api.openai.com`.
#   - Toolchain downloads: `dl.espressif.com`, `pypi.org`, `crates.io`,
#     `proxy.golang.org`.
#   - Observability: `sentry.io`, `grafana.net`, etc.
#
# If you need LAN access (to devices on your home/office network), uncomment
# the LAN_NETWORK block near the bottom of this file.

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# CONFIG: allowed hostnames
# Default allowlist contains only what Claude Code itself needs to function.
# Add your project's services below the commented "examples" block.
# ============================================================================
ALLOWED_DOMAINS=(
    # ----- Anthropic (required for Claude Code to work) -----
    api.anthropic.com
    console.anthropic.com
    statsig.anthropic.com
    sentry.io
    statsig.com

    # ----- GitHub (required for gh CLI + git push/pull over HTTPS) -----
    github.com
    api.github.com
    raw.githubusercontent.com
    objects.githubusercontent.com
    github-releases.githubusercontent.com
    codeload.github.com
    ghcr.io

    # ----- npm (required for any node-based project) -----
    registry.npmjs.org

    # ----- VS Code (extension updates) -----
    marketplace.visualstudio.com
    vscode.blob.core.windows.net
    update.code.visualstudio.com
    vscode.download.prss.microsoft.com
    vsmarketplacebadges.dev

    # ========================================================================
    # Examples — delete or replace for your project. These are NOT active by
    # default; uncomment the ones you need or add your own.
    # ========================================================================

    # ----- Example: Vercel deploy target -----
    # vercel.com
    # api.vercel.com
    # myapp.vercel.app

    # ----- Example: Supabase (dnsmasq auto-matches all *.supabase.co) -----
    # supabase.co

    # ----- Example: Fly.io -----
    # fly.io
    # api.machines.dev

    # ----- Example: Cloudflare -----
    # cloudflare.com
    # api.cloudflare.com
    # workers.cloudflare.com

    # ----- Example: Stripe API -----
    # api.stripe.com

    # ----- Example: OpenAI API -----
    # api.openai.com

    # ----- Example: Python toolchain -----
    # pypi.org
    # files.pythonhosted.org

    # ----- Example: Go modules -----
    # proxy.golang.org
    # sum.golang.org

    # ----- Example: Rust crates -----
    # crates.io
    # static.crates.io

    # ----- Example: Arduino / ESP32 toolchain -----
    # downloads.arduino.cc
    # dl.espressif.com
    # arduino.esp8266.com

    # ----- Example: Google Fonts (next/font fetches at build time) -----
    # fonts.googleapis.com
    # fonts.gstatic.com
)

UPSTREAM_DNS_1="1.1.1.1"
UPSTREAM_DNS_2="8.8.8.8"

# ============================================================================
# STEP 1: Reset firewall to a known-open state
# ============================================================================
echo "Flushing existing firewall rules..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT
ipset destroy allowed-domains 2>/dev/null || true

# ============================================================================
# STEP 2: Create the ipset that dnsmasq will populate
# ============================================================================
# 'timeout 86400' means IPs age out after 24h if not re-resolved. Keeps the
# set bounded even if a CDN rotates aggressively.
ipset create allowed-domains hash:ip timeout 86400

# ============================================================================
# STEP 3: Configure dnsmasq
# ============================================================================
echo "Configuring dnsmasq..."
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/allowlist.conf <<DNSMASQ_CONF
# Ignore /etc/resolv.conf; only use the upstream servers listed below.
no-resolv
server=$UPSTREAM_DNS_1
server=$UPSTREAM_DNS_2

# Listen only on loopback.
listen-address=127.0.0.1
bind-interfaces

cache-size=1000

# Don't read /etc/hosts (avoids surprises).
no-hosts

# DENY-BY-DEFAULT: NXDOMAIN for anything not explicitly allowed below.
address=/#/
DNSMASQ_CONF

# For each allowed hostname:
#   server=/<host>/<upstream>     -> route queries for this host to upstream
#   ipset=/<host>/allowed-domains -> add resolved IPs to the iptables ipset
{
    echo ""
    echo "# Allowed hostnames"
    for domain in "${ALLOWED_DOMAINS[@]}"; do
        echo "server=/$domain/$UPSTREAM_DNS_1"
        echo "server=/$domain/$UPSTREAM_DNS_2"
        echo "ipset=/$domain/allowed-domains"
    done
} >> /etc/dnsmasq.d/allowlist.conf

# ============================================================================
# STEP 4: Point container's DNS at dnsmasq
# ============================================================================
echo "Setting /etc/resolv.conf to use dnsmasq..."
cat > /etc/resolv.conf <<RESOLV_CONF
# Managed by init-firewall.sh
nameserver 127.0.0.1
options timeout:2 attempts:2
RESOLV_CONF

# ============================================================================
# STEP 5: Start dnsmasq
# ============================================================================
echo "Starting dnsmasq..."
pkill -x dnsmasq 2>/dev/null || true
sleep 1
dnsmasq --conf-file=/etc/dnsmasq.d/allowlist.conf
sleep 1

if ! pgrep -x dnsmasq > /dev/null; then
    echo "ERROR: dnsmasq failed to start"
    exit 1
fi

# ============================================================================
# STEP 6: Pre-populate ipset by resolving each allowed domain once
# ============================================================================
echo "Pre-resolving allowed domains..."
for domain in "${ALLOWED_DOMAINS[@]}"; do
    dig @127.0.0.1 +short +time=2 +tries=1 A "$domain" > /dev/null 2>&1 || true
done

# ============================================================================
# STEP 7: Allow Docker host network (needed for VS Code server ↔ extension)
# ============================================================================
HOST_IP=$(ip route | awk '/default/ {print $3; exit}')
HOST_NETWORK=""
if [ -n "$HOST_IP" ]; then
    HOST_NETWORK=$(echo "$HOST_IP" | sed 's|\.[0-9]*$|.0/24|')
    echo "Host network: $HOST_NETWORK"
fi

# ============================================================================
# STEP 8: Apply iptables rules
# ============================================================================
echo "Applying firewall rules..."

# Loopback (dnsmasq lives here).
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Return traffic.
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Docker host network (VS Code extension host).
if [ -n "$HOST_NETWORK" ]; then
    iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
    iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
fi

# ============================================================================
# Example: LAN access — uncomment if you need the container to reach
# devices on your home / office LAN (e.g. local dev servers, IoT boards,
# printers). Change the subnet to match your LAN.
# ============================================================================
# LAN_NETWORK="192.168.1.0/24"
# iptables -A OUTPUT -d "$LAN_NETWORK" -j ACCEPT
# iptables -A INPUT -s "$LAN_NETWORK" -j ACCEPT

# DNS queries to local dnsmasq (loopback already covers this, but explicit).
iptables -A OUTPUT -p udp -d 127.0.0.1 --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp -d 127.0.0.1 --dport 53 -j ACCEPT

# dnsmasq itself needs to reach upstream DNS.
iptables -A OUTPUT -p udp -d "$UPSTREAM_DNS_1" --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp -d "$UPSTREAM_DNS_1" --dport 53 -j ACCEPT
iptables -A OUTPUT -p udp -d "$UPSTREAM_DNS_2" --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp -d "$UPSTREAM_DNS_2" --dport 53 -j ACCEPT

# Main rule: allow OUTPUT to any IP the ipset contains. dnsmasq adds IPs
# here on-demand as allowed hostnames are resolved.
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Default: DROP everything else.
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Explicit REJECT at end so blocked connections fail fast with a clear error.
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# ============================================================================
# STEP 9: Verify
# ============================================================================
echo ""
echo "=== Verification ==="

if curl --connect-timeout 5 -o /dev/null -s https://api.anthropic.com > /dev/null 2>&1; then
    echo "OK: api.anthropic.com reachable"
else
    echo "FAIL: api.anthropic.com NOT reachable"
fi

if curl --connect-timeout 3 -o /dev/null -s https://example.com 2>/dev/null; then
    echo "FAIL: example.com reachable (should be blocked)"
else
    echo "OK: example.com blocked"
fi

if curl --connect-timeout 3 -o /dev/null -s http://1.2.3.4 2>/dev/null; then
    echo "FAIL: direct IP 1.2.3.4 reachable (should be blocked)"
else
    echo "OK: direct IP 1.2.3.4 blocked"
fi

echo ""
echo "Firewall configured. Allowed domains:"
printf '  %s\n' "${ALLOWED_DOMAINS[@]}"
