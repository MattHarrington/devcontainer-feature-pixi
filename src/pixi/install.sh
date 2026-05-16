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

INSTALL_DIR="/usr/local/bin"
GITHUB_REPO="prefix-dev/pixi"

echo "Activating feature 'pixi' (requested version: ${PIXI_VERSION})"

if [ "$(id -u)" -ne 0 ]; then
    echo "(!) This feature's install.sh must be run as root." >&2
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
        echo "(!) No supported package manager found; cannot install: $*" >&2
        return 1
    fi
}

missing=""
command -v tar >/dev/null 2>&1 || missing="${missing} tar"
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    missing="${missing} ca-certificates curl"
fi
if [ -n "${missing}" ]; then
    echo "Installing prerequisites:${missing}"
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
        echo "(!) Unsupported architecture: ${machine}" >&2
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

echo "Downloading pixi from: ${url}"
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${url}" -o "${tmp_dir}/${asset}"
else
    wget -q -O "${tmp_dir}/${asset}" "${url}"
fi

tar -xzf "${tmp_dir}/${asset}" -C "${tmp_dir}"

if [ ! -f "${tmp_dir}/pixi" ]; then
    echo "(!) The 'pixi' binary was not found inside ${asset}." >&2
    exit 1
fi

cp "${tmp_dir}/pixi" "${INSTALL_DIR}/pixi"
chmod 0755 "${INSTALL_DIR}/pixi"

echo "pixi installed: $("${INSTALL_DIR}/pixi" --version)"
echo "Feature 'pixi' done. 'pixi' is on PATH for all users at ${INSTALL_DIR}/pixi."
