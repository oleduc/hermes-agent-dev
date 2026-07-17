# hermes-agent-dev

A batteries-included, container development image built on top of
[`nousresearch/hermes-agent`](https://hub.docker.com/r/nousresearch/hermes-agent).
It layers a complete fullstack toolchain onto the Hermes agent so the agent
can build, test and ship software in **Python**, **Rust** and
**JavaScript/TypeScript** — covering both **web development** and **native
Linux (GUI) application development** — and can drive **Podman**, connect to
**SSH** hosts, and emit **Wake-on-LAN** packets.

- **Base image:** `docker.io/nousresearch/hermes-agent:latest` (Debian 13 "trixie")
- **Published to:** GitHub Container Registry — `ghcr.io/oleduc/hermes-agent-dev`
- **License:** MIT

---

## What's inside

### Languages & runtimes

| Language | Toolchain |
| --- | --- |
| **Python** | `python3`, `pip`, `venv`, `python3-dev`, [`uv`](https://github.com/astral-sh/uv), `pipx`, [`poetry`](https://python-poetry.org/) |
| **Rust** | `rustup` + stable toolchain (system-wide), `clippy`, `rustfmt`, `cargo-watch`, `cargo-edit` |
| **JS/TS** | Node.js LTS, `npm`, `pnpm` & `yarn` (via corepack), `typescript`, `ts-node` |

### Build & native toolchain

`build-essential` (gcc/g++/make), `clang`, `lld`, `cmake`, `ninja-build`,
`pkg-config`, `libssl-dev` — everything needed to compile native binaries and
link against system libraries.

### Native Linux GUI app development

- **GTK / Tauri:** `libgtk-3-dev`, `libglib2.0-dev`, `librsvg2-dev`,
  `libayatana-appindicator3-dev`, `libwebkit2gtk-4.1-dev`, `libsoup-3.0-dev`,
  plus the [`@tauri-apps/cli`](https://tauri.app/).
- **Electron / Qt / PySide runtime libraries:** the X11, GL/EGL, GBM/DRM,
  audio (ALSA) and accessibility libraries these frameworks need to launch a
  window (`libnss3`, `libgbm1`, `libgl1`, `libegl1`, `libasound2`,
  `libxkbcommon0`, `libxcomposite1`, `libxrandr2`, …).

> These give you a runnable native app toolchain. For an app to actually
> render a window at runtime you still need a display — an X/Wayland server on
> the host, an `Xvfb` virtual display in CI, or an `--device`/socket mount.

### Containers — Podman

`podman`, `buildah` and `skopeo`, configured for **rootless** operation
(`uidmap`, `slirp4netns`, `fuse-overlayfs`) plus `podman-compose`. The image
ships `/etc/containers/storage.conf` and `containers.conf` tuned to run inside
an unprivileged container/CI environment (fuse-overlayfs storage, cgroupfs
manager, file event logger).

### Networking

- **SSH:** `openssh-client`, `sshpass`, `rsync` for remote access and file sync.
- **Wake-on-LAN:** both `wakeonlan` (UDP magic packet) and `etherwake`
  (raw Ethernet frame) so you can wake hosts on the LAN.
- Diagnostics: `iproute2`, `iputils-ping`.

### Misc CLI

`git`, `curl`, `wget`, `jq`, `ripgrep`, `unzip`, `xz-utils`, `gnupg`.

---

## Usage

### Pull the published image

```bash
podman pull ghcr.io/oleduc/hermes-agent-dev:latest
# or
docker pull ghcr.io/oleduc/hermes-agent-dev:latest
```

### Build locally

```bash
docker build -t hermes-agent-dev .
```

### Run an interactive shell

```bash
docker run --rm -it hermes-agent-dev bash
```

### Verify the toolchains

```bash
docker run --rm hermes-agent-dev bash -lc '
  python3 --version && uv --version && poetry --version
  node --version && pnpm --version && tsc --version
  rustc --version && cargo --version && cargo clippy --version
  podman --version && buildah --version && skopeo --version
  ssh -V && wakeonlan --help | head -1
'
```

### Podman-in-container

Rootless Podman needs a user namespace. Run the container with the
appropriate namespace/keep-id options:

```bash
# Rootless podman inside the image
docker run --rm -it \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  --device /dev/fuse \
  hermes-agent-dev bash -lc 'podman info && podman run --rm docker.io/library/alpine echo hello'
```

`--device /dev/fuse` enables the `fuse-overlayfs` storage driver; the
`--security-opt` flags relax the defaults enough for nested containers. On a
host with cgroups v2 you can drop `seccomp=unconfined`.

### Connect to an SSH host

```bash
docker run --rm -it \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  hermes-agent-dev \
  ssh user@remote-host
```

### Emit a Wake-on-LAN packet

Wake-on-LAN broadcasts a "magic packet" on the local network, so the
container must share the host's network to reach the LAN broadcast domain:

```bash
# UDP magic packet (works across most setups)
docker run --rm --network host hermes-agent-dev \
  wakeonlan AA:BB:CC:DD:EE:FF

# Raw Ethernet frame on a specific interface (needs NET_RAW)
docker run --rm --network host --cap-add NET_RAW hermes-agent-dev \
  etherwake -i eth0 AA:BB:CC:DD:EE:FF
```

---

## Building & publishing (CI)

Images are built and pushed to GHCR by
[`.github/workflows/publish.yml`](.github/workflows/publish.yml). The workflow
triggers on **version tags** (`v*`) and publishes multi-tag images via
`docker/build-push-action` with GitHub Actions layer caching.

Cut a release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

This produces the following tags on `ghcr.io/oleduc/hermes-agent-dev`:

| Git tag | Image tags |
| --- | --- |
| `v1.2.3` | `1.2.3`, `1.2`, `1`, `latest` |

The workflow authenticates with the built-in `GITHUB_TOKEN` (needs
`packages: write`, already granted in the workflow), so no additional secrets
are required.

---

## Repository layout

```
.
├── Dockerfile                  # The image definition (see inline comments)
├── README.md                   # This file
├── LICENSE                     # MIT
└── .github/
    └── workflows/
        └── publish.yml         # Tag-triggered build & push to GHCR
```

## Extending the image

The `Dockerfile` groups packages by purpose with comments, so adding tooling
is straightforward — append to the relevant `apt-get`, `npm install -g`,
`cargo install` or `pipx install` step and rebuild. Keep related tools in the
same layer to avoid bloating the image with extra layers.
