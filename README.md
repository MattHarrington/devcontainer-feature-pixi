# Dev Container Features — pixi

[Dev Container Features](https://containers.dev/implementors/features/) for the
[`pixi`](https://pixi.sh) package manager.

## Contents

| Path            | Purpose                                          |
|-----------------|--------------------------------------------------|
| `src/pixi`      | The **pixi** Feature — installs the pixi binary. |
| `src/bioconda`  | The **bioconda** Feature — configures channels.  |
| `test/pixi`     | Automated tests for the **pixi** Feature.        |
| `test/bioconda` | Automated tests for the **bioconda** Feature.    |

## `pixi` Feature

Installs `pixi` as a system-wide binary at `/usr/local/bin/pixi`, available to
every user in the container.

The Feature downloads the prebuilt static `musl` binary directly from the
[`prefix-dev/pixi`](https://github.com/prefix-dev/pixi/releases) GitHub
releases. `x86_64` and `aarch64` Linux are supported. Any missing
prerequisites (`curl`/`wget`, `tar`, `ca-certificates`) are installed
automatically — `apt-get`, `apk`, `dnf`, `microdnf`, and `yum` base images are
supported.

### Usage

Reference the Feature from your `devcontainer.json`. While developing in this
repository, use the local path:

```jsonc
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
        "./src/pixi": {}
    }
}
```

Once the Feature is published to an OCI registry, reference it by its
identifier instead — for example:

```jsonc
"features": {
    "ghcr.io/OWNER/feature-pixi/pixi:1": {
        "version": "latest"
    }
}
```

### Options

| Option    | Type   | Default  | Description                                                                                       |
|-----------|--------|----------|---------------------------------------------------------------------------------------------------|
| `version` | string | `latest` | Version of pixi to install. Use `latest` or a semver such as `0.68.0` (a leading `v` is optional). |

### Example: pin a version

```jsonc
"features": {
    "./src/pixi": {
        "version": "0.68.0"
    }
}
```

## `bioconda` Feature

Configures the [Bioconda](https://bioconda.github.io) channel for `pixi`.

The Feature writes a system-wide pixi config at `/etc/pixi/config.toml` that
sets `default-channels` to `conda-forge` and `bioconda`. These become the
default channels for `pixi init` and `pixi global install`, so newly created
workspaces can resolve Bioconda packages without further configuration.
`conda-forge` is listed first because Bioconda depends on it and expects it to
take precedence.

This Feature only configures channels — it does not install the `pixi` binary.
Pair it with the `pixi` Feature; `installsAfter` ensures `bioconda` runs after
`pixi` when both are present.

### Usage

```jsonc
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
        "./src/pixi": {},
        "./src/bioconda": {}
    }
}
```

The `bioconda` Feature has no options.

## Testing

Tests run with the [`@devcontainers/cli`](https://github.com/devcontainers/cli):

```sh
npm install -g @devcontainers/cli

devcontainer features test \
    --features pixi --features bioconda \
    --base-image mcr.microsoft.com/devcontainers/base:ubuntu \
    .
```

This executes:

- `test/pixi/test.sh` — `pixi` with default options (`version: latest`).
- `test/pixi/pinned_version.sh` — the `pinned_version` scenario from
  `test/pixi/scenarios.json`, which pins `version` to an exact release.
- `test/bioconda/test.sh` — `bioconda` on its own; checks the pixi config is
  written.
- `test/bioconda/with_pixi.sh` — the `with_pixi` scenario from
  `test/bioconda/scenarios.json`, which installs both Features and checks that
  the installed `pixi` binary reads the Bioconda channel config.

## Notes

- Each `install.sh` is a POSIX `/bin/sh` script and runs as `root` during the
  image build, per the Dev Container Features specification.
- The bundled `pixi` binary is distributed under the
  [pixi license](https://github.com/prefix-dev/pixi/blob/main/LICENSE).
