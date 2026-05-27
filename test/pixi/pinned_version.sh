#!/bin/bash

# Scenario test for the 'pixi' feature's 'version' option.
#
# Exercises the 'pinned_version' scenario defined in scenarios.json, which
# installs an exact pixi release rather than 'latest'.

set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "pixi is on PATH"        bash -c "command -v pixi"
check "pixi version is pinned" bash -c "pixi --version | grep -w '0.68.0'"

reportResults
