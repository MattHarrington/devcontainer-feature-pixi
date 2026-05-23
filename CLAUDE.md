# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A repo holding a single [Dev Container Feature](https://containers.dev/implementors/features/) for the [pixi](https://pixi.sh) package manager. There is no application code and no build system (no `package.json`); the Feature is a `devcontainer-feature.json` manifest plus two POSIX scripts — `install.sh` (build time) and `post-create.sh` (the `postCreateCommand` helper). The "build" is the dev container CLI consuming the Feature; "test" is the CLI installing it into a real container and running assertions.

One Feature lives here:

- **`src/pixi`** — installs the `pixi` binary system-wide to `/usr/local/bin/pixi` by downloading the prebuilt static musl release from `prefix-dev/pixi`. Its `bioconda` boolean option (default `false`) additionally writes a system-wide pixi config at `/etc/pixi/config.toml` (`default-channels = ["conda-forge", "bioconda"]`). It also mounts a named Docker volume at the workspace `.pixi` so the package cache persists across rebuilds, and on first create bootstraps the workspace as a pixi project (see "The .pixi mount" and "Workspace bootstrap").

## Commands

Tests require the dev container CLI and Docker:

```sh
npm install -g @devcontainers/cli

# Run all tests for the pixi Feature (default-options test + every scenario)
devcontainer features test --features pixi \
    --base-image mcr.microsoft.com/devcontainers/base:ubuntu .
```

There is no separate runner for an individual scenario; `--features <name>` runs that Feature's `test.sh` plus every scenario script (see test layout below).

Local pre-commit validation used in this repo (no linter is configured beyond these):

```sh
python3 -m json.tool src/pixi/devcontainer-feature.json   # JSON well-formedness
sh -n src/pixi/install.sh src/pixi/post-create.sh         # shell syntax check
shellcheck src/pixi/install.sh                            # if shellcheck is installed
shellcheck -s sh src/pixi/post-create.sh                  # if shellcheck is installed
```

## Test harness conventions (requires reading test/ + the CLI docs together)

The `devcontainer features test` command discovers tests by filename convention — this is not obvious from any single file:

- `test/<feature>/test.sh` — the **default-options** test. Runs against an auto-generated `devcontainer.json` that includes the Feature with no options, so each option falls back to its default.
- `test/<feature>/scenarios.json` — maps a **scenario name** to a `devcontainer.json` fragment (base image + features with explicit options).
- `test/<feature>/<scenario>.sh` — the test body for that scenario. **The filename must match the scenario key in `scenarios.json`** (e.g. the `pinned_version` key pairs with `pinned_version.sh`). Adding a scenario means editing `scenarios.json` *and* adding the matching `.sh`.

Every test script sources `dev-container-features-test-lib` (bundled with the CLI) for the `check "<label>" <command>` and `reportResults` helpers. Tests run as `root`.

## Feature authoring conventions

- **`install.sh` is `/bin/sh` (POSIX), not bash**, and always runs as `root` at image build time. Scripts begin with `set -e` and assert `id -u` is 0. Keep them portable across the package managers the pixi Feature already handles (`apt-get`, `apk`, `dnf`, `microdnf`, `yum`).
- **Options reach `install.sh` as environment variables.** The dev container CLI uppercases the option id and replaces every non-`\w` character with `_` (so option `version` → `$VERSION`, and an option id like `exclude-newer` → `$EXCLUDE_NEWER`). Read them with a default, e.g. `PIXI_VERSION="${VERSION:-latest}"`.
- **LF line endings are mandatory** (`.gitattributes` enforces `eol=lf`). A CRLF shebang silently breaks the script inside a Linux container — never introduce CRLF.

## The bioconda option

The `bioconda` option (default `false`) is handled inside `src/pixi/install.sh` itself, *after* the binary is installed in the same script — so the config it writes at `/etc/pixi/config.toml` is read by the just-installed pixi. `/etc/pixi/config.toml` is pixi's lowest-priority (system-wide) config location, which is why writing there applies the channels to every user. Bioconda depends on conda-forge and expects it to take precedence, so `default-channels` lists `conda-forge` first. The `bioconda` scenario verifies this end-to-end (`pixi config list` shows the bioconda channel).

Note that pixi's global `config.toml` only supports a fixed set of keys (channels, mirrors, TLS, pypi-config, etc.). Per-workspace settings such as `exclude-newer` are **not** valid there — they live only in a project's `pixi.toml`/`pyproject.toml` `[workspace]` table.

## The .pixi mount

The Feature declares a `mounts` entry in `devcontainer-feature.json` that attaches a **named Docker volume** (`pixi-${devcontainerId}`) at `${containerWorkspaceFolder}/.pixi`, so pixi's package cache and per-project environments persist across container rebuilds.

It is deliberately a named volume, **not a host bind mount**. `.pixi` holds extracted conda packages, and conda package names can collide on a case-insensitive filesystem (macOS/Windows hosts), which corrupts a bind-mounted cache. A named volume always lives on Docker's case-sensitive Linux filesystem, sidestepping this. The tradeoff is that the cache persists but is not shared with / visible from the host. `${devcontainerId}` keys the volume to this dev container so it is stable across rebuilds without colliding with other projects.

Docker creates named-volume mount points owned by `root`, so a non-root dev container user cannot write to `.pixi` as mounted. Ownership is fixed by the **`postCreateCommand`** declared in `devcontainer-feature.json`, **not** in `install.sh`. This must run post-create rather than at build time: `install.sh` runs as root during the image build *before* the volume is mounted, so it cannot see or chown the mount. `postCreateCommand` runs on the live container after the volume is attached, as the (non-root) `remoteUser` — hence `sudo` (passwordless sudo is provided by the standard base images / the `common-utils` Feature this one `installsAfter`). Unlike `install.sh`, lifecycle commands are part of the Feature metadata, so the CLI *does* substitute `${containerWorkspaceFolder}` there. The chown is the first thing the `post-create.sh` helper does (see "Workspace bootstrap").

The `mount` scenario verifies this end-to-end (`.pixi` exists in the workspace and appears as its own mount point in `/proc/mounts`).

## Workspace bootstrap

`postCreateCommand` no longer runs an inline `chown`; it invokes a shipped helper, `/usr/local/share/pixi/post-create.sh "${containerWorkspaceFolder}"`. `install.sh` copies `src/pixi/post-create.sh` to that fixed path at build time because the Feature's source files only exist in the temporary build context — they are gone by the time lifecycle commands run, so the helper must already live in the image and be referenced by absolute path.

The helper (POSIX `/bin/sh`, runs as the `remoteUser`) does two things in order: (1) chown the mounted `.pixi` as described above, then (2) bootstrap the workspace as a pixi project. It treats the workspace as an **existing** project if there is a `pixi.toml` *or* a `pyproject.toml` containing a `[tool.pixi…]` table (matched with `grep`), in which case it runs `pixi install`; otherwise it runs `pixi init`. Checking `pyproject.toml` too avoids scaffolding a stray `pixi.toml` next to a pyproject-based pixi project.

The `init_install` scenario verifies this. Because `postCreateCommand` has already run by the time test scripts execute, the scenario also invokes the installed helper directly in scratch dirs to exercise both branches deterministically. The install-branch checks assert on the helper's printed branch decision (and that the existing manifest is untouched) rather than on `pixi install` completing, since a full solve needs the network.

## pixi binary install specifics (src/pixi/install.sh)

- Architecture is mapped to the release asset name: `x86_64`/`amd64` → `x86_64`, `aarch64`/`arm64` → `aarch64`; other arches error out. Asset is `pixi-<arch>-unknown-linux-musl.tar.gz`.
- `version: latest` uses GitHub's `releases/latest/download/…` redirect; a pinned version targets `releases/download/v<version>/…` with a leading `v` stripped/added so both `0.68.0` and `v0.68.0` work.
- Missing `curl`/`wget`, `tar`, and `ca-certificates` are installed on demand before download.
- When `bioconda=true`, the script writes `/etc/pixi/config.toml` after the binary install (see "The bioconda option" above).
