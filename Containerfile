FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl sudo ca-certificates jq zsh python3 perl \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/zsh robot \
    && echo "robot ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/robot \
    && chmod 0440 /etc/sudoers.d/robot

USER robot
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/robot/.local/bin:$PATH"

# Pre-create ~/.claude, so we can mount state from previous moat runs into it.
RUN mkdir -p /home/robot/.claude

USER root
