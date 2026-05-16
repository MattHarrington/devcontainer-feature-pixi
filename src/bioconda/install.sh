#!/bin/sh
#-------------------------------------------------------------------------------------------------------------
# Dev Container Feature: bioconda
#
# Configures the Bioconda channel for the pixi package manager by writing a
# system-wide pixi config at /etc/pixi/config.toml. This is the lowest-priority
# config location pixi reads, so it applies to every user in the container.
#
# This Feature only configures channels; it does not install pixi itself. Pair
# it with the 'pixi' Feature, which installs the pixi binary.
#
# 'install.sh' is always executed as root during the container image build.
# See: https://containers.dev/implementors/features/
#-------------------------------------------------------------------------------------------------------------
set -e

PIXI_CONFIG_FILE="/etc/pixi/config.toml"

echo "Activating feature 'bioconda'"

if [ "$(id -u)" -ne 0 ]; then
    echo "(!) This feature's install.sh must be run as root." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Write the system-wide pixi config. 'default-channels' seeds the channels for
# 'pixi init' and 'pixi global install'. Bioconda depends on conda-forge and
# expects it to take precedence, so conda-forge is listed first.
# ---------------------------------------------------------------------------
echo "Writing Bioconda channel config to ${PIXI_CONFIG_FILE}"
mkdir -p "$(dirname "${PIXI_CONFIG_FILE}")"
cat > "${PIXI_CONFIG_FILE}" <<'EOF'
# Managed by the 'bioconda' Dev Container Feature.
default-channels = ["conda-forge", "bioconda"]
EOF
chmod 0644 "${PIXI_CONFIG_FILE}"

if command -v pixi >/dev/null 2>&1; then
    echo "Bioconda channel configured for $(pixi --version)."
else
    echo "(!) 'pixi' was not found on PATH. Add the 'pixi' Feature so the" >&2
    echo "    Bioconda channel config at ${PIXI_CONFIG_FILE} is used." >&2
fi

echo "Feature 'bioconda' done."
