# syntax=docker/dockerfile:1

# Hermes Agent Dev — a batteries-included development image built on top of
# the Nous Research Hermes agent image. It provides complete toolchains for
# fullstack development in Python, Rust and JavaScript/TypeScript, covering
# both web development and native Linux (GUI) application development, plus
# tooling to drive Podman, connect to SSH hosts and emit Wake-on-LAN packets.
FROM docker.io/nousresearch/hermes-agent:latest

# Non-interactive apt for reproducible, unattended builds.
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# ---------------------------------------------------------------------------
# System packages
# ---------------------------------------------------------------------------
# Grouped by purpose so the layer is easy to audit and extend:
#   * Core CLI / VCS / build essentials for native compilation
#   * Networking: SSH client (+ sshpass) and Wake-on-LAN emitters
#   * Podman ecosystem (rootless-capable): podman, buildah, skopeo
#   * Native Linux app dev: GTK/WebKitGTK (Tauri/GTK), plus the X/GL/audio
#     runtime libraries that Electron and Qt apps need to launch
RUN apt-get update && apt-get install -y --no-install-recommends \
        # --- core / build ---
        git \
        curl \
        wget \
        ca-certificates \
        gnupg \
        lsb-release \
        unzip \
        xz-utils \
        jq \
        ripgrep \
        build-essential \
        pkg-config \
        cmake \
        ninja-build \
        clang \
        lld \
        libssl-dev \
        # --- python ---
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        pipx \
        # --- networking: ssh + wake-on-lan ---
        openssh-client \
        sshpass \
        rsync \
        iproute2 \
        iputils-ping \
        wakeonlan \
        etherwake \
        # --- podman ecosystem (rootless deps included) ---
        podman \
        buildah \
        skopeo \
        uidmap \
        slirp4netns \
        fuse-overlayfs \
        # --- native Linux GUI dev toolkits ---
        libgtk-3-dev \
        libglib2.0-dev \
        librsvg2-dev \
        libayatana-appindicator3-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# GUI runtime libraries that Electron / Qt / PySide need to launch. Several of
# these were renamed with a `t64` suffix in the 64-bit time_t transition
# (e.g. libasound2 -> libasound2t64), and names vary by base release, so
# install them best-effort per-package rather than failing the whole build.
RUN apt-get update \
    && for pkg in \
        libnss3 \
        libcups2 libcups2t64 \
        libatk1.0-0 libatk1.0-0t64 \
        libatk-bridge2.0-0 libatk-bridge2.0-0t64 \
        libasound2 libasound2t64 \
        libdrm2 libgbm1 libgl1 libegl1 \
        libxkbcommon0 libxcomposite1 libxdamage1 \
        libxrandr2 libxfixes3 libxext6 libxi6 ; do \
        apt-get install -y --no-install-recommends "$pkg" \
            || echo "hermes-agent-dev: optional GUI runtime lib '$pkg' unavailable, skipping" ; \
    done \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# WebKitGTK + libsoup for Tauri. The package names differ across Debian/Ubuntu
# releases (4.1/soup-3.0 on newer, 4.0/soup2.4 on older), so try the modern
# names first and transparently fall back to the legacy ones.
RUN apt-get update \
    && ( apt-get install -y --no-install-recommends \
            libwebkit2gtk-4.1-dev libsoup-3.0-dev \
      || apt-get install -y --no-install-recommends \
            libwebkit2gtk-4.0-dev libsoup2.4-dev ) \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Node.js (LTS) + JS/TS tooling
# ---------------------------------------------------------------------------
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    # corepack manages pnpm/yarn; also install a global TypeScript toolchain.
    && corepack enable \
    && corepack prepare pnpm@latest --activate \
    && corepack prepare yarn@stable --activate \
    && npm install -g typescript ts-node @tauri-apps/cli

# ---------------------------------------------------------------------------
# Rust (system-wide via rustup) + native-dev components and tooling
# ---------------------------------------------------------------------------
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --profile minimal \
        --component clippy rustfmt \
    # Fast incremental linker and a couple of ubiquitous cargo helpers.
    && cargo install --locked cargo-watch cargo-edit \
    && chmod -R a+w /usr/local/rustup /usr/local/cargo

# ---------------------------------------------------------------------------
# Python tooling: uv (fast resolver/installer) + pipx-managed apps
# ---------------------------------------------------------------------------
ENV PATH=/root/.local/bin:$PATH \
    PIPX_HOME=/usr/local/pipx \
    PIPX_BIN_DIR=/usr/local/bin
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh \
    && pipx install poetry \
    && pipx install podman-compose

# ---------------------------------------------------------------------------
# Rootless Podman configuration
# ---------------------------------------------------------------------------
# Use fuse-overlayfs and disable cgroups so Podman works inside unprivileged
# containers/CI without a systemd session.
RUN mkdir -p /etc/containers \
    && printf '[storage]\ndriver = "overlay"\n\n[storage.options.overlay]\nmount_program = "/usr/bin/fuse-overlayfs"\n' \
        > /etc/containers/storage.conf \
    && printf '[engine]\ncgroup_manager = "cgroupfs"\nevents_logger = "file"\n' \
        > /etc/containers/containers.conf

LABEL org.opencontainers.image.title="hermes-agent-dev" \
      org.opencontainers.image.description="Fullstack (Python/Rust/JS-TS) + native Linux app dev image with Podman, SSH and Wake-on-LAN tooling, built on nousresearch/hermes-agent." \
      org.opencontainers.image.source="https://github.com/oleduc/hermes-agent-dev" \
      org.opencontainers.image.licenses="MIT"
