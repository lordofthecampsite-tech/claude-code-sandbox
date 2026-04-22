# syntax=docker/dockerfile:1.4
#
# Claude Code Sandbox — base image.
#
# A minimal Node 20 container with the firewall toolchain (iptables + ipset
# + dnsmasq), GitHub CLI, and Claude Code preinstalled. Everything in
# /home/node is owned by the non-root `node` user.
#
# Kept small on purpose. Language toolchains (Python, Go, Rust, arduino-cli)
# and project-specific services are NOT preinstalled — add them via the
# "Examples" section at the bottom of this file, or via postCreateCommand
# in devcontainer.json.

FROM node:20

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

# Basic development tools + the firewall toolchain (iptables/ipset/dnsmasq).
# BuildKit cache mounts keep apt downloads across rebuilds.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  dnsmasq \
  curl \
  wget \
  ca-certificates

# Global npm prefix owned by the node user.
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

# Persist bash history across container rebuilds (mounted named volume in
# devcontainer.json).
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Help user code (including Claude Code) detect it's running in a devcontainer.
ENV DEVCONTAINER=true

# Create workspace + config dirs with correct ownership.
RUN mkdir -p /workspace /home/node/.claude && \
  chown -R node:node /workspace /home/node/.claude

WORKDIR /workspace

# git-delta for nicer `git diff` output.
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

USER node

ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano

# oh-my-zsh with git + fzf plugins. Purely QoL; delete the whole block if
# you prefer vanilla bash.
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# Claude Code CLI. Kept as the last install so frequent Claude updates
# don't invalidate layer cache for anything above.
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Firewall init script. postStartCommand in devcontainer.json invokes it.
COPY init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall && \
  echo "node ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/node-all && \
  chmod 0440 /etc/sudoers.d/node-all
USER node

# ============================================================================
# Examples — delete or replace for your project.
# ============================================================================
# The sections below show how the original author of this template extended
# the base image for a specific project. They are commented out so a fresh
# clone builds with only the generic base. Uncomment what you need, or ask
# Claude Code to do it (see /setup).
#
# ----- Example 1: arduino-cli + ESP32 toolchain (embedded-firmware project) -----
# RUN mkdir -p /home/node/.local/bin && \
#   curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | BINDIR=/home/node/.local/bin sh
# ENV PATH=$PATH:/home/node/.local/bin
# # ESP32 core install itself belongs in postCreateCommand (devcontainer.json)
# # so the ~200 MB toolchain lives in a named volume, not the image.
#
# ----- Example 2: Python 3.12 + pipx -----
# USER root
# RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
#     --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
#     apt-get update && apt-get install -y --no-install-recommends python3 python3-pip python3-venv pipx
# USER node
# RUN pipx ensurepath
#
# ----- Example 3: Go 1.22 -----
# USER root
# RUN curl -fsSL https://go.dev/dl/go1.22.0.linux-$(dpkg --print-architecture).tar.gz | tar -C /usr/local -xz
# ENV PATH=$PATH:/usr/local/go/bin
# USER node
#
# ----- Example 4: Rust via rustup -----
# RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
# ENV PATH=$PATH:/home/node/.cargo/bin
#
# ============================================================================
