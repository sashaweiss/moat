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
