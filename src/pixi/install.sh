#!/bin/sh
#-------------------------------------------------------------------------------------------------------------
# Dev Container Feature: pixi
#
# Installs the pixi package manager (https://pixi.sh) as a system-wide binary at
# /usr/local/bin/pixi by downloading the prebuilt static musl binary from the
# prefix-dev/pixi GitHub releases.
#
# 'install.sh' is always executed as root during the container image build.
# See: https://containers.dev/implementors/features/
#-------------------------------------------------------------------------------------------------------------
set -e

# ---------------------------------------------------------------------------
# Options (declared in devcontainer-feature.json). The dev container CLI passes
# each option to this script as an uppercased environment variable.
# ---------------------------------------------------------------------------
PIXI_VERSION="${VERSION:-latest}"
PIXI_BIOCONDA="${BIOCONDA:-false}"

INSTALL_DIR="/usr/local/bin"
GITHUB_REPO="prefix-dev/pixi"
PIXI_CONFIG_FILE="/etc/pixi/config.toml"

printf "Activating feature 'pixi' (requested version: %s, bioconda: %s)\n" "${PIXI_VERSION}" "${PIXI_BIOCONDA}"

if [ "$(id -u)" -ne 0 ]; then
    printf "(!) This feature's install.sh must be run as root.\n" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Install any missing prerequisites (a downloader, tar, CA certificates) using
# whichever package manager the base image provides.
# ---------------------------------------------------------------------------
install_packages() {
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y --no-install-recommends "$@"
        rm -rf /var/lib/apt/lists/*
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache "$@"
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y "$@"
    elif command -v microdnf >/dev/null 2>&1; then
        microdnf install -y "$@"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y "$@"
    else
        printf "(!) No supported package manager found; cannot install: %s\n" "$*" >&2
        return 1
    fi
}

missing=""
command -v tar >/dev/null 2>&1 || missing="${missing} tar"
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    missing="${missing} ca-certificates curl"
fi
if [ -n "${missing}" ]; then
    printf "Installing prerequisites: %s\n" "${missing}"
    # Word-splitting ${missing} into separate package arguments is intentional.
    # shellcheck disable=SC2086
    install_packages ${missing}
fi

# ---------------------------------------------------------------------------
# Map the machine architecture to the pixi release asset name.
# ---------------------------------------------------------------------------
machine="$(uname -m)"
case "${machine}" in
    x86_64 | amd64)  pixi_arch="x86_64" ;;
    aarch64 | arm64) pixi_arch="aarch64" ;;
    *)
        printf "(!) Unsupported architecture: %s\n" "${machine}" >&2
        exit 1
        ;;
esac

asset="pixi-${pixi_arch}-unknown-linux-musl.tar.gz"

# ---------------------------------------------------------------------------
# Resolve the download URL. 'latest' uses GitHub's latest-release redirect; a
# pinned version targets the matching release tag (a leading 'v' is optional).
# ---------------------------------------------------------------------------
if [ "${PIXI_VERSION}" = "latest" ]; then
    url="https://github.com/${GITHUB_REPO}/releases/latest/download/${asset}"
else
    tag="v${PIXI_VERSION#v}"
    url="https://github.com/${GITHUB_REPO}/releases/download/${tag}/${asset}"
fi

# ---------------------------------------------------------------------------
# Download, extract, and install the binary.
# ---------------------------------------------------------------------------
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

printf "Downloading pixi from: %s\n" "${url}"
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${url}" -o "${tmp_dir}/${asset}"
else
    wget -q -O "${tmp_dir}/${asset}" "${url}"
fi

tar -xzf "${tmp_dir}/${asset}" -C "${tmp_dir}"

if [ ! -f "${tmp_dir}/pixi" ]; then
    printf "(!) The 'pixi' binary was not found inside %s.\n" "${asset}" >&2
    exit 1
fi

cp "${tmp_dir}/pixi" "${INSTALL_DIR}/pixi"
chmod 0755 "${INSTALL_DIR}/pixi"

printf "pixi installed: %s\n" "$("${INSTALL_DIR}/pixi" --version)"

# ---------------------------------------------------------------------------
# Optionally configure the Bioconda channel by writing a system-wide pixi
# config at /etc/pixi/config.toml. This is the lowest-priority config location
# pixi reads, so it applies to every user in the container. 'default-channels'
# seeds the channels for 'pixi init' and 'pixi global install'. Bioconda depends
# on conda-forge and expects it to take precedence, so conda-forge is first.
# ---------------------------------------------------------------------------
if [ "${PIXI_BIOCONDA}" = "true" ]; then
    printf "Writing Bioconda channel config to %s\n" "${PIXI_CONFIG_FILE}"
    mkdir -p "$(dirname "${PIXI_CONFIG_FILE}")"
    cat >"${PIXI_CONFIG_FILE}" <<'EOF'
# Managed by the 'pixi' Dev Container Feature ('bioconda' option).
default-channels = ["conda-forge", "bioconda"]
EOF
    chmod 0644 "${PIXI_CONFIG_FILE}"
    printf "Bioconda channel configured for %s.\n" "$("${INSTALL_DIR}/pixi" --version)"
fi

# ---------------------------------------------------------------------------
# Fix ownership of the .pixi mount point so the dev container user can write
# to it. Docker always creates named-volume mount points owned by root; the
# dev container CLI exposes the non-root user via _REMOTE_USER.
# ---------------------------------------------------------------------------
if [ -n "${_REMOTE_USER}" ] && [ "${_REMOTE_USER}" != "root" ]; then
    pixi_mount="${containerWorkspaceFolder:-/workspaces}/.pixi"
    mkdir -p "${pixi_mount}"
    chown "${_REMOTE_USER}" "${pixi_mount}"
fi

printf "Feature 'pixi' done. 'pixi' is on PATH for all users at %s/pixi.\n" "${INSTALL_DIR}"
