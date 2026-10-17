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
