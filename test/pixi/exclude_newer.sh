#!/bin/bash
# shellcheck disable=SC2016

# Scenario test for the 'pixi' feature's 'exclude-newer' option.
#
# Exercises the 'exclude_newer' scenario defined in scenarios.json, which
# installs pixi with exclude-newer=7d. The option is a per-workspace pixi.toml
# [workspace] key (it is *not* valid in the global /etc/pixi/config.toml), so
# the feature applies it from the postCreateCommand helper: install.sh bakes the
# chosen value into the image at /usr/local/share/pixi/exclude-newer, and the
# helper writes it into the pixi.toml produced by 'pixi init'. The default '0d'
# means "no cutoff" and is treated as disabled (no key written).
#
# postCreateCommand has already run against the test workspace by the time this
# script executes, so we drive the helper directly in scratch directories to
# exercise every branch deterministically without needing the network: the
# value is written into a fresh init manifest, inside the [workspace] table; a
# '0d' value writes nothing; and an existing project (the install branch) is
# never touched.
#
# These checks run as the non-root remoteUser, and the baked value file is
# root-owned, so we never overwrite it. To test a value other than the real
# baked '7d', we run a *copy* of the helper whose EXCLUDE_NEWER_FILE constant is
# repointed (via sed) at a writable scratch file -- no privileges needed, and
# the installed image is left untouched.

set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

HELPER=/usr/local/share/pixi/post-create.sh
VALUE_FILE=/usr/local/share/pixi/exclude-newer

check "helper installed"        test -x "$HELPER"
check "exclude-newer value baked from option" \
    bash -c 'test "$(cat '"$VALUE_FILE"')" = "7d"'

# --- init branch: the baked value lands inside the [workspace] table -----------
# 'pixi init' writes [workspace] first and may emit further tables after it, so
# the key must be inserted within [workspace], not appended at end of file. We
# assert the line exists and that it precedes any later table header.
check "init writes exclude-newer into [workspace]" bash -c '
    d="$(mktemp -d)"
    "'"$HELPER"'" "$d" >/dev/null
    grep -q "^exclude-newer = \"7d\"$" "$d/pixi.toml" || exit 1
    ws="$(grep -n "^\[workspace\]" "$d/pixi.toml" | head -n1 | cut -d: -f1)"
    en="$(grep -n "^exclude-newer = " "$d/pixi.toml" | head -n1 | cut -d: -f1)"
    # The key sits after the [workspace] header and before the next table (if any).
    next="$(awk "NR>$ws && /^\[/ {print NR; exit}" "$d/pixi.toml")"
    test "$en" -gt "$ws" || exit 1
    [ -z "$next" ] || test "$en" -lt "$next"
'

# --- default 0d disables the feature: no exclude-newer line is written ---------
# Run a helper copy whose value file is a scratch file holding '0d', so the
# root-owned baked file is never written.
check "0d writes no exclude-newer line" bash -c '
    work="$(mktemp -d)"
    printf "0d\n" > "$work/value"
    sed "s#^EXCLUDE_NEWER_FILE=.*#EXCLUDE_NEWER_FILE=\"$work/value\"#" \
        "'"$HELPER"'" > "$work/helper.sh"
    chmod +x "$work/helper.sh"
    d="$(mktemp -d)"
    "$work/helper.sh" "$d" >/dev/null
    test -f "$d/pixi.toml" || exit 1
    ! grep -q "^exclude-newer = " "$d/pixi.toml"
'

# --- install branch: an existing project is never edited -----------------------
# Point the (installed) helper at a workspace that already has a pixi.toml. The
# install branch never reads the value file, so the real baked '7d' is fine to
# leave in place. The helper must take the install branch and leave the manifest
# byte-for-byte unchanged (no exclude-newer injected). A networkless
# 'pixi install' may fail; '|| true' keeps that from masking the assertions.
check "existing project keeps its manifest unchanged" bash -c '
    d="$(mktemp -d)"
    cat > "$d/pixi.toml" <<EOF
[workspace]
name = "preexisting"
channels = ["conda-forge"]
platforms = ["linux-64"]
EOF
    before="$(cat "$d/pixi.toml")"
    "'"$HELPER"'" "$d" >/dev/null 2>&1 || true
    test "$(cat "$d/pixi.toml")" = "$before" &&
        ! grep -q "^exclude-newer = " "$d/pixi.toml"
'

reportResults
