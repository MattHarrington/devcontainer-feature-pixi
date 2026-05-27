#!/bin/bash

# Scenario test for the 'pixi' feature's 'bioconda' option.
#
# Exercises the 'bioconda' scenario defined in scenarios.json, which installs
# pixi with bioconda=true. Because the option is handled inside the pixi
# feature's own install.sh (after the binary is installed), this verifies both
# that the system-wide config is written and that the installed pixi binary
# actually reads the Bioconda channel.

set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "pixi is on PATH"            bash -c "command -v pixi"
check "system pixi config exists"  test -f /etc/pixi/config.toml
check "bioconda channel configured"    bash -c "grep -q 'bioconda' /etc/pixi/config.toml"
check "conda-forge channel configured" bash -c "grep -q 'conda-forge' /etc/pixi/config.toml"
check "pixi reads bioconda config" bash -c "pixi config list | grep -q 'bioconda'"

reportResults
