#!/bin/bash
# shellcheck disable=SC2016

# Scenario test for the 'pixi' feature's named-volume mounts.
#
# The feature declares a 'mounts' entry that attaches a named Docker volume
# (pixi-${devcontainerId}) at ${containerWorkspaceFolder}/.pixi, so pixi's
# per-project environments and other .pixi project data persist across rebuilds
# without passing through a (possibly case-insensitive) host filesystem.
#
# It also mounts the shared pixi cache volume at $PIXI_CACHE_DIR so pixi
# downloads can persist outside the container filesystem.
#
# The test harness runs from the container's workspace folder, so '.pixi'
# resolves to the mount target. We assert the directory exists and that it is
# its own mount point (i.e. the volume is actually attached, not just an empty
# dir created on the image layer).
#
# Docker creates named-volume mount points owned by root; the feature's
# postCreateCommand helper chowns them to the remoteUser (the non-root 'vscode'
# user on this base image) so the mounted directories are writable. We assert
# that chown took effect by checking each mount is owned by the user the helper
# ran as, not root.

set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

cache_dir="${PIXI_CACHE_DIR:-/mnt/pixi-cache}"

check "pixi is on PATH"        bash -c "command -v pixi"
check ".pixi exists in workspace" test -d "$(pwd)/.pixi"
check ".pixi is a mount point"    bash -c 'grep -qF " $(pwd)/.pixi " /proc/mounts'
check "\$PIXI_CACHE_DIR exists" test -d "$cache_dir"
check "\$PIXI_CACHE_DIR is a mount point" \
    env CACHE_DIR="$cache_dir" bash -c 'grep -qF " ${CACHE_DIR} " /proc/mounts'

# postCreateCommand runs as the remoteUser, who also owns the workspace folder,
# so '.pixi' should end up with that same owner -- not root, which is how Docker
# mounts the named volume. Comparing against the workspace owner avoids
# hardcoding the base image's 'vscode' user (test scripts themselves run as root).
check ".pixi is owned by the remoteUser, not root" \
    bash -c 'test "$(stat -c "%U" "$(pwd)/.pixi")" = "$(stat -c "%U" "$(pwd)")"'
check ".pixi is not owned by root" \
    bash -c 'test "$(stat -c "%U" "$(pwd)/.pixi")" != "root"'
check "\$PIXI_CACHE_DIR is owned by the remoteUser, not root" \
    env CACHE_DIR="$cache_dir" bash -c 'test "$(stat -c "%U" "$CACHE_DIR")" = "$(stat -c "%U" "$(pwd)")"'
check "\$PIXI_CACHE_DIR is not owned by root" \
    env CACHE_DIR="$cache_dir" bash -c 'test "$(stat -c "%U" "$CACHE_DIR")" != "root"'

reportResults
