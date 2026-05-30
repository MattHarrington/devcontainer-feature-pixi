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
# Options (declared in devcontainer-feature.json). The Dev Container CLI passes
# each option to this script as an uppercased environment variable.
# ---------------------------------------------------------------------------
PIXI_VERSION="${VERSION:-latest}"
PIXI_BIOCONDA="${BIOCONDA:-false}"
PIXI_EXCLUDE_NEWER="${EXCLUDE_NEWER:-0d}"

INSTALL_DIR="/usr/local/bin"
GITHUB_REPO="prefix-dev/pixi"
PIXI_CONFIG_FILE="/etc/pixi/config.toml"
POST_CREATE_SRC="$(dirname "$0")/post-create.sh"
POST_CREATE_DEST="/usr/local/share/pixi/post-create.sh"
EXCLUDE_NEWER_FILE="/usr/local/share/pixi/exclude-newer"

printf "Activating feature 'pixi' (requested version: %s, bioconda: %s, exclude-newer: %s)\n" \
    "${PIXI_VERSION}" "${PIXI_BIOCONDA}" "${PIXI_EXCLUDE_NEWER}"

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
has_ca_certificates() {
    [ -s /etc/ssl/certs/ca-certificates.crt ] ||
        [ -s /etc/pki/tls/certs/ca-bundle.crt ] ||
        [ -s /etc/ssl/cert.pem ]
}
has_ca_certificates || missing="${missing} ca-certificates"
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    missing="${missing} curl"
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
# Install the postCreateCommand helper to a fixed path. The feature's source
# files are only present in this temporary build context, so the helper is
# copied into the image here; devcontainer-feature.json's 'postCreateCommand'
# then invokes it by absolute path on the live container (after the named
# volumes are mounted).
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "${POST_CREATE_DEST}")"
cp "${POST_CREATE_SRC}" "${POST_CREATE_DEST}"
chmod 0755 "${POST_CREATE_DEST}"

# ---------------------------------------------------------------------------
# Persist the 'exclude-newer' option for the postCreateCommand helper. Option
# values reach this script as environment variables, but lifecycle command
# strings only substitute a fixed set of variables (not arbitrary options), so
# the value cannot be passed to post-create.sh as an argument. Bake it into the
# image here (as install.sh already does for the helper itself) so the helper
# can read it on the live container; it applies the value to 'pixi init'.
# ---------------------------------------------------------------------------
printf '%s\n' "${PIXI_EXCLUDE_NEWER}" >"${EXCLUDE_NEWER_FILE}"
chmod 0644 "${EXCLUDE_NEWER_FILE}"

printf "Feature 'pixi' done. 'pixi' is on PATH for all users at %s/pixi.\n" "${INSTALL_DIR}"
