
# pixi (pixi)

Installs the pixi package manager (https://pixi.sh) as a system-wide binary.

## Example Usage

```json
"features": {
    "ghcr.io/MattHarrington/devcontainer-feature-pixi/pixi:0": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Version of pixi to install. Use 'latest' or a semver such as '0.68.0' (a leading 'v' is optional). | string | latest |
| exclude-newer | Package 'cooldown' for newly scaffolded projects: when not '0d', write exclude-newer = "<value>" into the [workspace] table of the pixi.toml created by 'pixi init', so packages published within that window are excluded from solves. Accepts any pixi-supported value (a relative duration such as '7d', or a YYYY-MM-DD / RFC 3339 date). '0d' (the default) disables it. Requires pixi >= 0.67.0. | string | 0d |
| bioconda | Configure the Bioconda channel by writing a system-wide pixi config at /etc/pixi/config.toml with default-channels = ["conda-forge", "bioconda"]. Only affects new projects. | boolean | false |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/MattHarrington/devcontainer-feature-pixi/blob/main/src/pixi/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
