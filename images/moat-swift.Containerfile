# Extends moat:base with a Swift toolchain managed by swiftly.

FROM moat:base

USER root

# Install dependencies for swiftly and the Swift toolchain.
RUN apt-get update && apt-get install -y --no-install-recommends \
    binutils gcc gnupg2 libcurl4-openssl-dev libedit-dev libicu-dev \
    libncurses-dev libpython3-dev libsqlite3-dev libstdc++-12-dev \
    libxml2-dev pkg-config unzip uuid-dev zip \
    && rm -rf /var/lib/apt/lists/*

# Install swiftly and the toolchain as robot, so Claude can install other
# toolchains (e.g., for a project's .swift-version) without sudo.
USER robot
ENV SWIFTLY_HOME_DIR="/home/robot/.local/share/swiftly"
ENV SWIFTLY_BIN_DIR="/home/robot/.local/share/swiftly/bin"
ENV SWIFTLY_TOOLCHAINS_DIR="/home/robot/.local/share/swiftly/toolchains"
ENV PATH="$SWIFTLY_BIN_DIR:$PATH"
RUN cd /tmp \
    && curl -fsSLO "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz" \
    && tar -xzf "swiftly-$(uname -m).tar.gz" \
    && ./swiftly init --assume-yes --no-modify-profile --quiet-shell-followup \
    && rm -f swiftly "swiftly-$(uname -m).tar.gz" \
    && swift --version

# Install SwiftFormat from its prebuilt, statically-linked release binaries,
# as robot, so Claude can install other versions without sudo.
ARG SWIFTFORMAT_VERSION=0.64.0
RUN cd /tmp \
    && case "$(uname -m)" in \
        x86_64) asset=swiftformat_linux ;; \
        aarch64) asset=swiftformat_linux_aarch64 ;; \
        *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
    esac \
    && curl -fsSLO "https://github.com/nicklockwood/SwiftFormat/releases/download/$SWIFTFORMAT_VERSION/$asset.zip" \
    && unzip -q "$asset.zip" \
    && install -D -m 0755 "$asset" /home/robot/.local/bin/swiftformat \
    && rm -f "$asset" "$asset.zip" \
    && swiftformat --version


# Seed Claude plugins outside of ~/.claude, since that's managed by moat.
ENV CLAUDE_CODE_PLUGIN_SEED_DIR="/home/robot/.local/share/claude-plugin-seed"

# Use a throwaway HOME to add the swift-lsp Claude plugin (backed by the
# `sourcekit-lsp` that ships with Swift). This installs the actual plugin to
# the durable SEED_DIR above, but lets us discard changes that these commands
# make in HOME such as writing Claude configs to enable the plugin.
RUN export HOME="$(mktemp -d)" \
        CLAUDE_CODE_PLUGIN_CACHE_DIR="$CLAUDE_CODE_PLUGIN_SEED_DIR" \
    && claude plugin marketplace add anthropics/claude-plugins-official \
    && claude plugin install swift-lsp@claude-plugins-official \
    && rm -rf "$HOME"

# Enable the swift-lsp Claude plugin via managed settings, since moat manages
# the user-level ~/.claude/settings.json.
USER root
RUN mkdir -p /etc/claude-code \
    && jq -n '{ enabledPlugins: { "swift-lsp@claude-plugins-official": true } }' \
        > /etc/claude-code/managed-settings.json

# Bootstrap ~/.claude with the seed's plugin registry, so the plugin is ready
# on a workspace's first launch. Adjust it to match how Claude Code stores
# seeded, managed plugins, so it doesn't rewrite them and prompt for a reload.
RUN dir=/etc/moat/bootstrap/.claude/plugins \
    && mkdir -p "$dir" \
    && jq 'map_values(.autoUpdate = false)' \
        "$CLAUDE_CODE_PLUGIN_SEED_DIR/known_marketplaces.json" \
        > "$dir/known_marketplaces.json" \
    && jq '.plugins |= map_values(map(.scope = "managed"))' \
        "$CLAUDE_CODE_PLUGIN_SEED_DIR/installed_plugins.json" \
        > "$dir/installed_plugins.json"
USER robot
