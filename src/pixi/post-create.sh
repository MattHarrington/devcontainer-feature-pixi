#!/bin/sh
#-------------------------------------------------------------------------------------------------------------
# Dev Container Feature: pixi -- postCreateCommand helper
#
# Runs once on the live container after the named volumes are mounted.
# 'install.sh' copies this script to a fixed path at image build time and
# devcontainer-feature.json invokes it from 'postCreateCommand'.
#
# Responsibilities, in order:
#   1. Take ownership of the mounted named volumes (Docker creates the mount
#      points owned by root, so the non-root remoteUser otherwise cannot write).
#   2. Bootstrap the workspace: if it is already a pixi project, install its
#      environment ('pixi install'); otherwise scaffold a new one ('pixi init')
#      and, when the 'exclude-newer' option is set, record it in the new
#      pixi.toml.
#
# Runs as the (possibly non-root) remoteUser, hence privileged ownership repair
# when needed.
# See: https://containers.dev/implementors/features/#lifecycle
#-------------------------------------------------------------------------------------------------------------
set -eu

# The workspace folder is the first argument (devcontainer-feature.json passes
# ${containerWorkspaceFolder}, which the CLI substitutes in lifecycle commands).
workspace="${1:?workspace folder argument is required}"

# install.sh bakes the chosen 'exclude-newer' option value here at build time
# (lifecycle commands cannot receive arbitrary option values, so it is read
# from the image rather than passed as an argument). '0d' -- the option default
# -- means "current time", i.e. no real cutoff, and is treated as "disabled".
EXCLUDE_NEWER_FILE="/usr/local/share/pixi/exclude-newer"
PIXI_CACHE_DIR="${PIXI_CACHE_DIR:-/mnt/pixi-cache}"

cd "$workspace"

# ---------------------------------------------------------------------------
# 1. Own the mounted named volumes so the remoteUser can write them.
# ---------------------------------------------------------------------------
own_mounted_dir() {
    dir="$1"
    label="$2"

    [ -d "$dir" ] || return 0

    owner="$(id -un):$(id -gn)"
    if [ "$(id -u)" -eq 0 ]; then
        chown "$owner" "$dir"
    elif command -v sudo >/dev/null 2>&1; then
        sudo chown "$owner" "$dir"
    else
        printf "pixi: cannot chown %s; sudo is not available for user '%s'.\n" "$label" "$(id -un)" >&2
        exit 1
    fi
}

own_mounted_dir "$workspace/.pixi" ".pixi"
own_mounted_dir "$PIXI_CACHE_DIR" "\$PIXI_CACHE_DIR"

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

# Record the 'exclude-newer' option in a freshly scaffolded pixi.toml. Only
# called from the 'pixi init' branch, so it never edits a manifest the user
# brought themselves. Skips the default '0d' (disabled). The key is inserted
# *inside* the [workspace] table -- right after its header line -- because
# 'pixi init' may emit further tables ([dependencies], [tasks], ...) after it,
# so appending at end-of-file would land the key under the wrong table. A light
# validation rejects characters that have no place in a humantime/date value
# (and would otherwise let a value break out of the quoted TOML string); pixi
# does the semantic validation when it next solves. The value is passed to awk
# as a variable, never interpolated into the program text.
apply_exclude_newer() {
    [ -f "$EXCLUDE_NEWER_FILE" ] || return 0

    exclude_newer="$(cat "$EXCLUDE_NEWER_FILE")"
    case "$exclude_newer" in
        "" | 0d) return 0 ;;
        *[!0-9A-Za-z:.+-]*)
            printf "pixi: ignoring invalid exclude-newer value '%s'.\n" "$exclude_newer" >&2
            return 0
            ;;
    esac

    if ! grep -q '^[[:space:]]*\[workspace\]' "$workspace/pixi.toml"; then
        printf "pixi: no [workspace] table in pixi.toml; skipping exclude-newer.\n" >&2
        return 0
    fi

    printf "pixi: setting exclude-newer = \"%s\" in pixi.toml.\n" "$exclude_newer"
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT INT TERM
    awk -v val="$exclude_newer" '
        { print }
        !done && /^[[:space:]]*\[workspace\]/ {
            printf "exclude-newer = \"%s\"\n", val
            done = 1
        }
    ' "$workspace/pixi.toml" >"$tmp"
    cat "$tmp" >"$workspace/pixi.toml"
    rm -f "$tmp"
    trap - EXIT INT TERM
}

if is_pixi_project; then
    printf "pixi: existing project detected, running 'pixi install'.\n"
    pixi install
else
    printf "pixi: no project manifest found, running 'pixi init'.\n"
    pixi init
    apply_exclude_newer
fi
