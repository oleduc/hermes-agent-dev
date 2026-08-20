#!/usr/bin/env bash
# Runtime smoke test for the built image.
#
# The PR/publish CI only proves the image *builds*; this proves the base
# Hermes CLI and the key toolchains actually *run* inside it. Invoked from the
# GitHub Actions workflow with a locally-loaded image ref, e.g.:
#
#   ci/smoke-test.sh hermes-agent-dev:ci
#
# We override the image entrypoint with `bash`: the default entrypoint launches
# the s6 supervision tree (a long-running server) and would both fail to exit
# and intercept leading-dash args like `--version`. Under `bash -c` the image's
# ENV PATH still applies, so `hermes` resolves to the /opt/hermes/bin shim
# (which re-execs as the hermes user) and the toolchain binaries resolve too.
set -euo pipefail

IMAGE="${1:?usage: smoke-test.sh <image-ref>}"

echo ":: smoke-testing ${IMAGE}"
docker run --rm --entrypoint bash "${IMAGE}" -c '
  set -euo pipefail

  echo "== hermes =="
  # Prove the base command still works on top of our layers. Accept --version,
  # falling back to --help for older/newer flag surfaces.
  hermes --version || hermes --help

  echo "== node (must be 26.x per Hermes v0.20.0 requirement) =="
  node --version
  node --version | grep -Eq "^v26\." || { echo "ERROR: expected Node 26.x"; exit 1; }

  echo "== javascript / typescript toolchain =="
  corepack --version
  pnpm --version
  yarn --version
  tsc --version

  echo "== python toolchain =="
  python3 --version
  uv --version
  poetry --version

  echo "== rust toolchain =="
  rustc --version
  cargo --version
  cargo clippy --version

  echo "== container / ops tooling =="
  # podman/buildah share containers/storage. Run as root inside a plain CI
  # container there is no XDG runtime dir to derive a runroot from, so point
  # them at throwaway dirs with the vfs driver (no /dev/fuse needed). This is
  # a binary liveness check; real usage is rootless (see the README).
  podman  --root /tmp/pstore --runroot /tmp/prun --storage-driver vfs version
  buildah --root /tmp/pstore --runroot /tmp/prun --storage-driver vfs version
  skopeo --version

  echo ":: all smoke checks passed"
'
