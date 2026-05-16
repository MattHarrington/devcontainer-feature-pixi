#!/bin/bash

# Default-options test for the 'pixi' feature.
#
# This test runs against an auto-generated devcontainer.json that includes the
# 'pixi' feature with no options, so 'version' falls back to its default
# ('latest'). Tests run as 'root' by default.
#
# Run with:
#   devcontainer features test \
#       --features pixi \
#       --base-image mcr.microsoft.com/devcontainers/base:ubuntu \
#       .

set -e

# Provides the 'check' and 'reportResults' commands, bundled with the dev
# container CLI. See https://github.com/devcontainers/cli/blob/main/docs/features/test.md
source dev-container-features-test-lib

check "pixi is on PATH"            bash -c "command -v pixi"
check "pixi installed system-wide" test -x /usr/local/bin/pixi
check "pixi reports a version"     bash -c "pixi --version | grep -E '^pixi '"
check "pixi info runs"             bash -c "pixi info"

reportResults
