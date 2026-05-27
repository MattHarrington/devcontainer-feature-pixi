# AGENTS.md

Guidance for Codex and other coding agents working in this repository.

## Repository Shape

This repo contains one Dev Container Feature for the `pixi` package manager.
There is no application code and no project build system such as
`package.json`.

- `src/pixi/devcontainer-feature.json` is the Feature manifest.
- `src/pixi/install.sh` runs at image build time as `root`.
- `src/pixi/post-create.sh` is copied into the image and runs from
  `postCreateCommand` after the workspace volume is mounted.
- `test/pixi` contains Dev Container Feature tests.

Use "Dev Container" in prose. Keep literal names like `devcontainer.json`,
`devcontainer-feature.json`, `@devcontainers/cli`, and the `devcontainer`
command exactly as written.

## Commands

Full behavior tests require Docker and the Dev Container CLI:

```sh
devcontainer features test --features pixi \
    --base-image mcr.microsoft.com/devcontainers/base:ubuntu .
```

Run this full suite before opening a PR when behavior changes. It runs the
default-options test plus every scenario in `test/pixi/scenarios.json`.

Light local validation:

```sh
python3 -m json.tool src/pixi/devcontainer-feature.json
python3 -m json.tool test/pixi/scenarios.json
sh -n src/pixi/install.sh src/pixi/post-create.sh
bash -n test/pixi/test.sh test/pixi/*.sh
shellcheck src/pixi/install.sh
shellcheck -s sh src/pixi/post-create.sh
shellcheck test/pixi/*.sh
```

`shellcheck` may not be installed locally; note that if you cannot run it.

## Test Layout

The Dev Container CLI discovers tests by convention:

- `test/pixi/test.sh` is the default-options test.
- `test/pixi/scenarios.json` maps scenario names to `devcontainer.json`
  fragments.
- `test/pixi/<scenario>.sh` is the script for the matching scenario key.

Adding a scenario requires both a new key in `scenarios.json` and a matching
shell script with the same basename.

Do not assume scenario tests run as `root`. On
`mcr.microsoft.com/devcontainers/base:ubuntu`, checks commonly run as the
non-root `vscode` `remoteUser`. Use `sudo` only when a privileged write is
actually needed.

## Feature Conventions

`install.sh` is POSIX `/bin/sh`, not bash. It should stay portable across the
package managers already handled here: `apt-get`, `apk`, `dnf`, `microdnf`,
and `yum`.

Feature options arrive in `install.sh` as uppercased environment variables with
non-word characters converted to underscores. For example:

- `version` -> `VERSION`
- `bioconda` -> `BIOCONDA`
- `exclude-newer` -> `EXCLUDE_NEWER`

Lifecycle command strings do not receive arbitrary option values. This is why
`install.sh` writes the `exclude-newer` value to
`/usr/local/share/pixi/exclude-newer` for `post-create.sh` to read later.

Keep LF line endings. A CRLF shebang will break inside Linux containers.

## Important Behavior

The Feature installs `/usr/local/bin/pixi` by downloading the static musl
release asset from `prefix-dev/pixi`.

The `bioconda` option is handled in `install.sh` by writing
`/etc/pixi/config.toml` with:

```toml
default-channels = ["conda-forge", "bioconda"]
```

The `exclude-newer` option is a per-workspace `[workspace]` key, not a global
pixi config key. It is applied only after `pixi init` creates a new
`pixi.toml`, and it must be inserted inside the `[workspace]` table. The
default `0d` is treated as disabled and should write no key.

The `.pixi` cache is a named Docker volume mounted at
`${containerWorkspaceFolder}/.pixi`. It is deliberately not a host bind mount.
`post-create.sh` chowns that mounted directory after the container is created,
because `install.sh` runs before the volume exists.

## Workspace Bootstrap

`post-create.sh` first fixes `.pixi` ownership, then bootstraps the workspace:

- If `pixi.toml` exists, run `pixi install`.
- If `pyproject.toml` contains a `[tool.pixi...]` table, run `pixi install`.
- Otherwise run `pixi init`, then apply `exclude-newer` if enabled.

Tests for the bootstrap helper often invoke `/usr/local/share/pixi/post-create.sh`
directly in scratch directories to avoid relying on network-dependent solves.
