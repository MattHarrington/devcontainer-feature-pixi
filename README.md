# Dev Container Feature — pixi

A [Dev Container Feature](https://containers.dev/implementors/features/) for the
[`pixi`](https://pixi.sh) package manager.

## Contents

| Path        | Purpose                                          |
|-------------|--------------------------------------------------|
| `src/pixi`  | The **pixi** Feature — installs the pixi binary. |
| `test/pixi` | Automated tests for the **pixi** Feature.        |

## `pixi` Feature

Installs `pixi` as a system-wide binary at `/usr/local/bin/pixi`, available to
every user in the container.

The Feature downloads the prebuilt static `musl` binary directly from the
[`prefix-dev/pixi`](https://github.com/prefix-dev/pixi/releases) GitHub
releases. `x86_64` and `aarch64` Linux are supported. Any missing
prerequisites (`curl`/`wget`, `tar`, `ca-certificates`) are installed
automatically — `apt-get`, `apk`, `dnf`, `microdnf`, and `yum` base images are
supported.

On first create the Feature also mounts a persistent package cache at the
workspace `.pixi` and bootstraps the workspace as a pixi project — see
[The `.pixi` mount](#the-pixi-mount) and
[Workspace bootstrap](#workspace-bootstrap) below.

### Required: create the `.pixi` mount point on the host

The Feature mounts a named Docker volume at `${containerWorkspaceFolder}/.pixi`
(see [The `.pixi` mount](#the-pixi-mount)). If the host-side mount point does not
already exist, Docker creates it for you — but owned by `root`, which is not
what you want. To avoid that, your `devcontainer.json` **must** create it before
the container starts with an `initializeCommand`:

```jsonc
"initializeCommand": "mkdir -p ${localWorkspaceFolder}/.pixi"
```

`initializeCommand` runs on the host before the container is created, which is
the only lifecycle hook that runs early enough. Without it — and if you don't
already have a `.pixi` directory in your workspace — Docker creates the host-side
mount point itself, owned by `root`. That leaves a `root`-owned `.pixi`
directory in your workspace after you stop the dev container, which you might
then need elevated privileges to remove. Creating the directory yourself first
means it is owned by you. A complete example is shown under [Usage](#usage).

### Usage

Reference the Feature from your `devcontainer.json`. While developing in this
repository, use the local path:

```jsonc
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "initializeCommand": "mkdir -p ${localWorkspaceFolder}/.pixi",
    "features": {
        "./src/pixi": {}
    }
}
```

Once the Feature is published to an OCI registry, reference it by its
identifier instead — for example:

```jsonc
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "initializeCommand": "mkdir -p ${localWorkspaceFolder}/.pixi",
    "features": {
        "ghcr.io/OWNER/feature-pixi/pixi:1": {
            "version": "latest"
        }
    }
}
```

### Options

| Option     | Type    | Default  | Description                                                                                         |
|------------|---------|----------|-----------------------------------------------------------------------------------------------------|
| `version`  | string  | `latest` | Version of pixi to install. Use `latest` or a semver such as `0.68.0` (a leading `v` is optional).  |
| `bioconda` | boolean | `false`  | Configure the Bioconda channel by writing a system-wide pixi config (see [The `bioconda` option](#the-bioconda-option)). |

### Example: pin a version

```jsonc
"features": {
    "./src/pixi": {
        "version": "0.68.0"
    }
}
```

### The `bioconda` option

Setting `bioconda` to `true` configures the
[Bioconda](https://bioconda.github.io) channel for `pixi`. The Feature writes a
system-wide pixi config at `/etc/pixi/config.toml` that sets `default-channels`
to `conda-forge` and `bioconda`. These become the default channels for
`pixi init` and `pixi global install`, so newly created workspaces can resolve
Bioconda packages without further configuration. `conda-forge` is listed first
because Bioconda depends on it and expects it to take precedence.

```jsonc
"features": {
    "./src/pixi": {
        "bioconda": true
    }
}
```

`/etc/pixi/config.toml` is pixi's lowest-priority (system-wide) config location,
which is why the channels apply to every user. Note that per-workspace settings
such as `exclude-newer` are **not** valid there — those live only in a project's
`pixi.toml`/`pyproject.toml` `[workspace]` table.

### The `.pixi` mount

The Feature mounts a **named Docker volume** (`pixi-${devcontainerId}`) at
`${containerWorkspaceFolder}/.pixi`, so pixi's package cache and per-project
environments persist across container rebuilds.

It is deliberately a named volume, **not** a host bind mount. `.pixi` holds
extracted conda packages whose names can collide on a case-insensitive
filesystem (macOS/Windows hosts), which would corrupt a bind-mounted cache. A
named volume always lives on Docker's case-sensitive Linux filesystem,
sidestepping this. The tradeoff is that the cache persists but is not shared
with or visible from the host. `${devcontainerId}` keys the volume to this dev
container, so it is stable across rebuilds without colliding with other
projects.

As a safeguard, the Feature's `postCreateCommand` chowns `.pixi` to the
(non-root) container user on the live container after the volume is attached, so
the cache is writable even when the host-side mount point ended up owned by
`root`. This is why the `initializeCommand` above matters: it controls
ownership of the directory left behind on the host, which the in-container chown
cannot fix.

> **Remember:** add
> `"initializeCommand": "mkdir -p ${localWorkspaceFolder}/.pixi"` to your
> `devcontainer.json` so the host-side mount point is owned by you rather than
> by `root` (see
> [Required: create the `.pixi` mount point on the host](#required-create-the-pixi-mount-point-on-the-host)).

### Workspace bootstrap

After fixing the `.pixi` ownership, the `postCreateCommand` helper bootstraps
the workspace as a pixi project. If the workspace already contains a `pixi.toml`
— or a `pyproject.toml` with a `[tool.pixi…]` table — it runs `pixi install`;
otherwise it runs `pixi init` to scaffold a new project. Checking
`pyproject.toml` as well avoids scaffolding a stray `pixi.toml` next to a
pyproject-based pixi project.

## Testing

Tests run with the [`@devcontainers/cli`](https://github.com/devcontainers/cli):

```sh
npm install -g @devcontainers/cli

devcontainer features test \
    --features pixi \
    --base-image mcr.microsoft.com/devcontainers/base:ubuntu \
    .
```

This executes `test/pixi/test.sh` (the Feature with default options) plus every
scenario from `test/pixi/scenarios.json`:

- `test/pixi/test.sh` — `pixi` with default options (`version: latest`).
- `test/pixi/pinned_version.sh` — the `pinned_version` scenario, which pins
  `version` to an exact release.
- `test/pixi/bioconda.sh` — the `bioconda` scenario, which sets `bioconda: true`
  and checks the installed `pixi` binary reads the Bioconda channel config.
- `test/pixi/mount.sh` — the `mount` scenario, which checks `.pixi` exists in
  the workspace and appears as its own mount point.
- `test/pixi/init_install.sh` — the `init_install` scenario, which checks the
  workspace-bootstrap helper takes the `pixi init` and `pixi install` branches
  correctly.

## Notes

- `install.sh` is a POSIX `/bin/sh` script and runs as `root` during the
  image build, per the Dev Container Features specification.
- The bundled `pixi` binary is distributed under the
  [pixi license](https://github.com/prefix-dev/pixi/blob/main/LICENSE).
