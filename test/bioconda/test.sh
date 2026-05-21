#!/bin/bash

# Default-options test for the 'bioconda' feature.
#
# This test runs against an auto-generated devcontainer.json that includes the
# 'bioconda' feature on its own. It verifies the system-wide pixi config is
# written; the 'with_pixi' scenario covers pixi actually reading it.
#
# Run with:
#   devcontainer features test \
#       --features bioconda \
#       --base-image mcr.microsoft.com/devcontainers/base:ubuntu \
#       .

set -e

# Provides the 'check' and 'reportResults' commands, bundled with the dev
# container CLI. See https://github.com/devcontainers/cli/blob/main/docs/features/test.md
source dev-container-features-test-lib

check "system pixi config exists"      test -f /etc/pixi/config.toml
check "bioconda channel configured"    bash -c "grep -q 'bioconda' /etc/pixi/config.toml"
check "conda-forge channel configured" bash -c "grep -q 'conda-forge' /etc/pixi/config.toml"

reportResults
