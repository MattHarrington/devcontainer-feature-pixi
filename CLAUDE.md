# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A repo holding a single [Dev Container Feature](https://containers.dev/implementors/features/) for the [pixi](https://pixi.sh) package manager. There is no application code and no build system (no `package.json`); the Feature is a `devcontainer-feature.json` manifest plus a POSIX `install.sh`. The "build" is the dev container CLI consuming the Feature; "test" is the CLI installing it into a real container and running assertions.

One Feature lives here:

- **`src/pixi`** — installs the `pixi` binary system-wide to `/usr/local/bin/pixi` by downloading the prebuilt static musl release from `prefix-dev/pixi`. Its `bioconda` boolean option (default `false`) additionally writes a system-wide pixi config at `/etc/pixi/config.toml` (`default-channels = ["conda-forge", "bioconda"]`).

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
sh -n src/pixi/install.sh                                 # shell syntax check
shellcheck src/pixi/install.sh                            # if shellcheck is installed
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

## pixi binary install specifics (src/pixi/install.sh)

- Architecture is mapped to the release asset name: `x86_64`/`amd64` → `x86_64`, `aarch64`/`arm64` → `aarch64`; other arches error out. Asset is `pixi-<arch>-unknown-linux-musl.tar.gz`.
- `version: latest` uses GitHub's `releases/latest/download/…` redirect; a pinned version targets `releases/download/v<version>/…` with a leading `v` stripped/added so both `0.68.0` and `v0.68.0` work.
- Missing `curl`/`wget`, `tar`, and `ca-certificates` are installed on demand before download.
- When `bioconda=true`, the script writes `/etc/pixi/config.toml` after the binary install (see "The bioconda option" above).
