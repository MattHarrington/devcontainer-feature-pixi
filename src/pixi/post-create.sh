#!/bin/sh
#-------------------------------------------------------------------------------------------------------------
# Dev Container Feature: pixi -- postCreateCommand helper
#
# Runs once on the live container after the named '.pixi' volume is mounted.
# 'install.sh' copies this script to a fixed path at image build time and
# devcontainer-feature.json invokes it from 'postCreateCommand'.
#
# Responsibilities, in order:
#   1. Take ownership of the mounted '.pixi' volume (Docker creates the mount
#      point owned by root, so the non-root remoteUser otherwise cannot write).
#   2. Bootstrap the workspace: if it is already a pixi project, install its
#      environment ('pixi install'); otherwise scaffold a new one ('pixi init').
#
# Runs as the (possibly non-root) remoteUser, hence 'sudo' for the chown.
# See: https://containers.dev/implementors/features/#lifecycle
#-------------------------------------------------------------------------------------------------------------
set -eu

# The workspace folder is the first argument (devcontainer-feature.json passes
# ${containerWorkspaceFolder}, which the CLI substitutes in lifecycle commands).
workspace="${1:?workspace folder argument is required}"

cd "$workspace"

# ---------------------------------------------------------------------------
# 1. Own the mounted .pixi volume so the remoteUser can write the cache.
# ---------------------------------------------------------------------------
if [ -d "$workspace/.pixi" ]; then
    sudo chown "$(id -un):$(id -gn)" "$workspace/.pixi"
fi

# ---------------------------------------------------------------------------
# 2. Bootstrap the workspace as a pixi project.
#
# A workspace counts as an existing pixi project if it has a 'pixi.toml' or a
# 'pyproject.toml' carrying a '[tool.pixi]' table. In that case install the
# environment; otherwise scaffold a fresh project with 'pixi init'.
# ---------------------------------------------------------------------------
is_pixi_project() {
    [ -f "$workspace/pixi.toml" ] && return 0
    [ -f "$workspace/pyproject.toml" ] &&
        grep -q '^[[:space:]]*\[tool\.pixi' "$workspace/pyproject.toml" &&
        return 0
    return 1
}

if is_pixi_project; then
    printf "pixi: existing project detected, running 'pixi install'.\n"
    pixi install
else
    printf "pixi: no project manifest found, running 'pixi init'.\n"
    pixi init
fi
