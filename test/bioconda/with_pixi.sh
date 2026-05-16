#!/bin/bash

# Scenario test for the 'bioconda' feature alongside the 'pixi' feature.
#
# Exercises the 'with_pixi' scenario defined in scenarios.json, which installs
# both Features. 'installsAfter' ensures 'bioconda' runs after 'pixi', so this
# verifies the installed pixi binary actually reads the Bioconda channel config.

set -e

source dev-container-features-test-lib

check "pixi is on PATH"            bash -c "command -v pixi"
check "system pixi config exists"  test -f /etc/pixi/config.toml
check "pixi reads bioconda config" bash -c "pixi config list | grep -q 'bioconda'"

reportResults
