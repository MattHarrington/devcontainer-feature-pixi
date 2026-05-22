#!/bin/bash

# Scenario test for the 'pixi' feature's named-volume mount.
#
# The feature declares a 'mounts' entry that attaches a named Docker volume
# (pixi-${devcontainerId}) at ${containerWorkspaceFolder}/.pixi, so pixi's
# package cache and environments persist across rebuilds without passing
# through a (possibly case-insensitive) host filesystem.
#
# The test harness runs from the container's workspace folder, so '.pixi'
# resolves to the mount target. We assert the directory exists and that it is
# its own mount point (i.e. the volume is actually attached, not just an empty
# dir created on the image layer).

set -e

source dev-container-features-test-lib

check "pixi is on PATH"        bash -c "command -v pixi"
check ".pixi exists in workspace" test -d "$(pwd)/.pixi"
check ".pixi is a mount point"    bash -c 'grep -qF " $(pwd)/.pixi " /proc/mounts'

reportResults
