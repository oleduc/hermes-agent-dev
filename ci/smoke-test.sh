#!/usr/bin/env bash
# Runtime smoke test for the built image.
#
# The PR/publish CI proves the image *builds*; this proves the base Hermes CLI
# actually *runs* on top of our added layers. Invoked from the GitHub Actions
# workflow with a locally-loaded image ref, e.g.:
#
#   ci/smoke-test.sh hermes-agent-dev:ci
#
# We override the image entrypoint with `bash`: the default entrypoint launches
# the s6 supervision tree (a long-running server) and would both fail to exit
# and intercept leading-dash args like `--version`. Under `bash -c` the image's
# ENV PATH still applies, so `hermes` resolves to the /opt/hermes/bin shim
# (which re-execs as the hermes user).
#
# Scope is deliberately just the CLI liveness check. Deeper toolchain probes
# (podman, etc.) require runtime facilities the GitHub runner doesn't provide
# rootless, so they belong in local/manual testing, not pre-merge CI.
set -euo pipefail

IMAGE="${1:?usage: smoke-test.sh <image-ref>}"

echo ":: smoke-testing ${IMAGE}"
docker run --rm --entrypoint bash "${IMAGE}" -c '
  set -euo pipefail
  # Prove the base command still works on top of our layers. Accept --version,
  # falling back to --help for older/newer flag surfaces.
  hermes --version || hermes --help
'
echo ":: hermes CLI is runnable"
