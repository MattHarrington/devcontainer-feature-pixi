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
#
# Docker creates the named-volume mount point owned by root; the feature's
# postCreateCommand helper chowns it to the remoteUser (the non-root 'vscode'
# user on this base image) so the cache is writable. We assert that chown took
# effect by checking '.pixi' is owned by the user the helper ran as, not root.

set -e

source dev-container-features-test-lib

check "pixi is on PATH"        bash -c "command -v pixi"
check ".pixi exists in workspace" test -d "$(pwd)/.pixi"
check ".pixi is a mount point"    bash -c 'grep -qF " $(pwd)/.pixi " /proc/mounts'

# postCreateCommand runs as the remoteUser, who also owns the workspace folder,
# so '.pixi' should end up with that same owner -- not root, which is how Docker
# mounts the named volume. Comparing against the workspace owner avoids
# hardcoding the base image's 'vscode' user (test scripts themselves run as root).
check ".pixi is owned by the remoteUser, not root" \
    bash -c 'test "$(stat -c "%U" "$(pwd)/.pixi")" = "$(stat -c "%U" "$(pwd)")"'
check ".pixi is not owned by root" \
    bash -c 'test "$(stat -c "%U" "$(pwd)/.pixi")" != "root"'

reportResults
