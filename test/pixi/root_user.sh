#!/bin/bash
# shellcheck disable=SC2016

# Scenario test for running the 'pixi' feature with root as the remoteUser.
#
# The postCreateCommand helper normally uses sudo to chown the mounted .pixi
# volume for a non-root remoteUser. When the lifecycle command already runs as
# root, the helper should chown directly instead of requiring sudo.

set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "pixi is on PATH" bash -c "command -v pixi"
check "workspace bootstrapped" test -f "$(pwd)/pixi.toml"
check ".pixi is owned by root" \
    bash -c 'test "$(stat -c "%U" "$(pwd)/.pixi")" = "root"'
check ".pixi is writable by root" \
    bash -c 'touch "$(pwd)/.pixi/root-user-write-test"'

reportResults
