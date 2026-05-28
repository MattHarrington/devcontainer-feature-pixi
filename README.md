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
supported. The examples below use the Ubuntu base, but all three
[Dev Container base images](https://hub.docker.com/r/microsoft/devcontainers-base)
— Ubuntu, Debian, and Alpine — are supported, as are any Dev Container templates
built on top of those three base images. More generally, any base image that
supplies `sudo` (which the `postCreateCommand` uses to chown the `.pixi` mount)
will probably work too.

`pixi` itself works in Alpine containers, but Alpine may not be very useful for
some pixi projects. Many packages that pixi can install expect `glibc`, while
Alpine uses `musl`.

On first create the Feature also mounts a persistent package cache at the
workspace `.pixi` and bootstraps the workspace as a pixi project — see
[The `.pixi` mount](#the-pixi-mount) and
[Workspace bootstrap](#workspace-bootstrap) below.

### Optional: create the `.pixi` mount point on the host

The Feature mounts a named Docker volume at `${containerWorkspaceFolder}/.pixi`
(see [The `.pixi` mount](#the-pixi-mount)). If the host-side mount point does not
already exist, Docker creates it for you.

On Linux and macOS, Docker may create that host-side `.pixi` directory owned by
`root`. This is mostly cosmetic: it can look odd in `ls -l`, but the Feature
still chowns the mounted volume inside the container so pixi can write to it.
Linux users usually cannot `chown` or `chmod` the root-owned host-side mount
point, but they can remove it with `rm -r .pixi` after the Dev Container is
stopped.

If a root-owned `.pixi` mount point would bother you, you can create it before
the container starts with an `initializeCommand`:

```jsonc
"initializeCommand": "mkdir -p ${localWorkspaceFolder}/.pixi"
```

`initializeCommand` runs on the host before the container is created, which is
the only lifecycle hook that runs early enough. Creating the directory yourself
first means it is owned by you. The command above only works on Linux and macOS.
On Windows, Docker appears to create the `.pixi` mount point as the regular
user, so this is usually not an issue.

If you want a cross-platform `initializeCommand`, you can try:

```jsonc
{
    // First line is for Windows cmd.exe; second line is for macOS/Linux sh.
    "initializeCommand": "# 2>NUL & (cd \".pixi\" 2>NUL || mkdir \".pixi\") & if errorlevel 1 exit /B 1 & exit /B 0\nmkdir -p \".pixi\""
}
```

This works because the first line starts with `#`, so `sh` treats it as a
comment on macOS and Linux and then runs the second line. On Windows, the first
line is interpreted by `cmd.exe` instead, where the redirection and command
chaining make it create `.pixi` if needed and then exit successfully before the
macOS/Linux line runs. That lets one `initializeCommand` handle all platforms.

### Usage

Reference the Feature from your `devcontainer.json` by its registry identifier:

```jsonc
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
        "ghcr.io/MattHarrington/devcontainer-feature-pixi/pixi:0": {
            "version": "latest"
        }
    }
}
```

### Windows Docker Desktop setup

Docker Desktop on Windows recommends the WSL 2 backend. If you have trouble
launching Dev Containers on Windows — including Dev Containers that do not use
this Feature — check Docker Desktop's **Settings > Resources > WSL Integration**
page. WSL integration might need to be enabled for your default WSL
distribution; see Docker's
[Enable Docker in a WSL 2 distribution](https://docs.docker.com/desktop/features/wsl/#enable-docker-in-a-wsl-2-distribution)
documentation.

### Options

| Option          | Type    | Default  | Description                                                                                         |
|-----------------|---------|----------|-----------------------------------------------------------------------------------------------------|
| `version`       | string  | `latest` | Version of pixi to install. Use `latest` or a semver such as `0.68.0` (a leading `v` is optional).  |
| `exclude-newer` | string  | `0d`     | Package "cooldown" for a newly scaffolded project (see [The `exclude-newer` option](#the-exclude-newer-option)). Proposals: `7d`, `14d`, `30d`. `0d` (the default) disables it. |
| `bioconda`      | boolean | `false`  | Configure the Bioconda channel by writing a system-wide pixi config (see [The `bioconda` option](#the-bioconda-option)). |

### Example: pin a version

```jsonc
"features": {
    "ghcr.io/MattHarrington/devcontainer-feature-pixi/pixi:0": {
        "version": "0.68.0"
    }
}
```

### The `exclude-newer` option

`exclude-newer` sets a package "cooldown": pixi excludes any package published
more recently than the cutoff from its solves, which reduces the risk of pulling
in a freshly published (and possibly compromised) release. It is a per-workspace
setting that lives in the `[workspace]` table of a project's `pixi.toml` — it is
**not** valid in the system-wide `/etc/pixi/config.toml` — so the Feature applies
it where the value belongs: the [workspace-bootstrap helper](#workspace-bootstrap)
writes it into the `pixi.toml` that `pixi init` generates.

```jsonc
"features": {
    "ghcr.io/MattHarrington/devcontainer-feature-pixi/pixi:0": {
        "exclude-newer": "7d"
    }
}
```

With the example above, a workspace the Feature scaffolds gets:

```toml
[workspace]
exclude-newer = "7d"
# ...the rest of what `pixi init` writes
```

Notes:

- **Only newly scaffolded projects are affected.** The value is written **only**
  when the helper runs `pixi init` (the workspace had no manifest). If the
  workspace already contains a `pixi.toml` or a pyproject-based pixi project, the
  helper takes the `pixi install` branch and leaves your manifest untouched — set
  `exclude-newer` in your own manifest in that case.
- **`0d` (the default) disables it.** pixi treats `0d` as "the current time", i.e.
  no real cutoff, so the Feature writes nothing for it, keeping the scaffolded
  `pixi.toml` clean.
- **Proposals are hints, not limits.** The `7d`/`14d`/`30d` proposals are common
  cooldown windows, but the option is a free-form string: any value pixi accepts
  works — another relative duration (e.g. `90d`, `1h30m`) or an absolute
  `YYYY-MM-DD` / RFC 3339 date (e.g. `2025-01-01`). The Feature passes the value
  through and lets pixi validate it when it solves.
- **Requires pixi ≥ 0.67.0**, which introduced relative-duration values for
  `exclude-newer`. The default `latest` and any recent pinned `version` satisfy
  this; an absolute date works on older pixi too.

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
    "ghcr.io/MattHarrington/devcontainer-feature-pixi/pixi:0": {
        "bioconda": true
    }
}
```

`/etc/pixi/config.toml` is pixi's lowest-priority (system-wide) config location,
which is why the channels apply to every user. Because the channels live in this
system-wide config — not in a project manifest — the option **never modifies an
existing `pixi.toml`**; it only sets the default channels that a newly scaffolded
project inherits. A workspace that already has a `pixi.toml` keeps whatever
channels it declares. Note also that per-workspace settings such as
`exclude-newer` are **not** valid in `/etc/pixi/config.toml` — those live only in
a project's `pixi.toml`/`pyproject.toml` `[workspace]` table, which is exactly
where the [`exclude-newer` option](#the-exclude-newer-option) writes them.

### The `.pixi` mount

The Feature mounts a **named Docker volume** (`pixi-${devcontainerId}`) at
`${containerWorkspaceFolder}/.pixi`, so pixi's package cache and per-project
environments persist across container rebuilds.

It is deliberately a named volume, **not** a host bind mount. `.pixi` holds
extracted conda packages whose names can collide on a case-insensitive
filesystem (macOS/Windows hosts), which would corrupt a bind-mounted cache. A
named volume always lives on Docker's case-sensitive Linux filesystem,
sidestepping this. The tradeoff is that the cache persists but is not shared
with or visible from the host. `${devcontainerId}` keys the volume to this Dev
Container, so it is stable across rebuilds without colliding with other
projects.

As a safeguard, the Feature's `postCreateCommand` chowns `.pixi` to the
(non-root) container user on the live container after the volume is attached, so
the cache is writable even when the host-side mount point ended up owned by
`root`. The optional `initializeCommand` above only controls ownership of the
directory left behind on the host, which the in-container chown cannot fix.

If you already have a `.pixi` directory at the workspace root, Docker mounts its
volume **on top of** it, masking the original contents for the life of the
container — only the volume is visible at that path while the container runs.
When the container shuts down, Docker unmounts the volume and your original
`.pixi` directory becomes visible again, untouched.

> **Tip:** if a root-owned `.pixi` host-side mount point would bother you, add
> an `initializeCommand` to your `devcontainer.json` to create it first (see
> [Optional: create the `.pixi` mount point on the host](#optional-create-the-pixi-mount-point-on-the-host)).

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
- `test/pixi/root_user.sh` — the `root_user` scenario, which checks the
  post-create helper handles a `root` `remoteUser` without requiring `sudo`.
- `test/pixi/exclude_newer.sh` — the `exclude_newer` scenario, which sets
  `exclude-newer: 7d` and checks the helper writes the value into the
  `[workspace]` table of a freshly scaffolded `pixi.toml`, skips the `0d`
  default, and never edits an existing manifest.

## Notes

- `install.sh` is a POSIX `/bin/sh` script and runs as `root` during the
  image build, per the Dev Container Features specification.
- The bundled `pixi` binary is distributed under the
  [pixi license](https://github.com/prefix-dev/pixi/blob/main/LICENSE).
