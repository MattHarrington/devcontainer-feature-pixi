#!/bin/bash
# shellcheck disable=SC2016

# Scenario test for the 'pixi' feature's postCreateCommand bootstrap helper.
#
# The feature ships /usr/local/share/pixi/post-create.sh and wires it into
# 'postCreateCommand'. The helper chowns the mounted .pixi volume, then either
# scaffolds a new project ('pixi init') when no manifest is present or installs
# the environment ('pixi install') when the workspace is already a pixi project.
#
# postCreateCommand has already run against the test workspace by the time this
# script executes, so we also drive the helper directly in scratch directories
# to exercise both branches deterministically (init-on-empty, install-on-
# existing for both pixi.toml and a pyproject.toml [tool.pixi] table).

set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

HELPER=/usr/local/share/pixi/post-create.sh

check "helper installed"   test -x "$HELPER"
check "pixi is on PATH"     bash -c "command -v pixi"

# --- init branch: empty workspace gets a fresh pixi.toml -----------------------
check "init scaffolds pixi.toml" bash -c '
    d="$(mktemp -d)"
    "'"$HELPER"'" "$d" >/dev/null
    test -f "$d/pixi.toml"
'

# --- install branch: existing pixi.toml takes the install path -----------------
# The helper prints its chosen branch before running 'pixi install' (a full
# solve that needs the network), so we assert on the branch decision and the
# manifest being left untouched -- not on install completion. '|| true' lets a
# networkless 'pixi install' fail without masking the branch assertions.
check "existing pixi.toml -> install branch" bash -c '
    d="$(mktemp -d)"
    cat > "$d/pixi.toml" <<EOF
[workspace]
name = "preexisting"
channels = ["conda-forge"]
platforms = ["linux-64"]
EOF
    out="$("'"$HELPER"'" "$d" 2>&1 || true)"
    printf "%s\n" "$out" | grep -q "pixi install" &&
        grep -q "preexisting" "$d/pixi.toml"
'

# --- install branch: pyproject.toml with [tool.pixi] counts as a project -------
check "pyproject [tool.pixi] -> install branch" bash -c '
    d="$(mktemp -d)"
    cat > "$d/pyproject.toml" <<EOF
[tool.pixi.workspace]
channels = ["conda-forge"]
platforms = ["linux-64"]
EOF
    out="$("'"$HELPER"'" "$d" 2>&1 || true)"
    printf "%s\n" "$out" | grep -q "pixi install" &&
        test ! -f "$d/pixi.toml"
'

reportResults
