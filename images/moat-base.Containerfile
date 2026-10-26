FROM debian:bookworm-slim

# The tools available in the VM.
ARG TOOLS="\
    ca-certificates \
    curl \
    fd-find \
    git \
    jq \
    make \
    perl \
    python3 \
    ripgrep \
    sudo \
    zsh \
"

RUN apt-get update && apt-get install -y --no-install-recommends $TOOLS \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/zsh robot \
    && echo "robot ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/robot \
    && chmod 0440 /etc/sudoers.d/robot

USER robot
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/robot/.local/bin:$PATH"

# Pre-create ~/.claude, so we can mount state from previous moat runs into it.
RUN mkdir -p /home/robot/.claude
