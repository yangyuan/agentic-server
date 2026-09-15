#!/usr/bin/env bash
set -e

SUDO=(sudo)
if [ "$#" -eq 0 ]; then
    if [ "$EUID" -eq 0 ]; then
        printf 'Running as root requires --root. Run without sudo for user mode.\n' >&2
        exit 1
    fi
elif [ "$#" -eq 1 ] && [ "$1" = "--root" ]; then
    if [ "$EUID" -ne 0 ]; then
        printf 'Root mode requires root. Run: sudo -H bash "%s" --root\n' "$0" >&2
        exit 1
    fi
    SUDO=()
else
    printf 'Usage: bash "%s" [--root]\n' "$0" >&2
    exit 2
fi

URL_CODEX_PRIMARY_RUNTIME_LATEST="https://persistent.oaistatic.com/codex-primary-runtime/latest/linux-x64/LATEST.json"

PATH_CODEX_PRIMARY_RUNTIME="/opt/codex/runtimes/codex-primary-runtime"
PATH_CODEX_RUNTIMES_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/codex-runtimes"
PATH_TMP_WORK="$(mktemp -d)"

# Always remove the temporary working directory when the script exits.
trap 'rm -rf "$PATH_TMP_WORK"' EXIT

# Create the directories used for installed runtimes and Codex's runtime cache.
"${SUDO[@]}" mkdir -p /opt/codex/runtimes
mkdir -p "$PATH_CODEX_RUNTIMES_CACHE"

# Download metadata for the latest Linux x64 Codex Primary Runtime.
curl -fsSL "$URL_CODEX_PRIMARY_RUNTIME_LATEST" -o "$PATH_TMP_WORK/codex-primary-runtime.json"

# Read the runtime archive URL from LATEST.json.
URL_CODEX_PRIMARY_RUNTIME_ARCHIVE="$(python3 -c '
import json, sys
print(json.load(open(sys.argv[1]))["archiveUrl"])
' "$PATH_TMP_WORK/codex-primary-runtime.json")"

# Read the Node version used by this runtime.
VERSION_NODE="$(python3 -c '
import json, sys
print(json.load(open(sys.argv[1]))["nodeVersion"])
' "$PATH_TMP_WORK/codex-primary-runtime.json")"

# Download and extract the Codex Primary Runtime.
curl -fsSL "$URL_CODEX_PRIMARY_RUNTIME_ARCHIVE" -o "$PATH_TMP_WORK/codex-primary-runtime.tar.xz"
"${SUDO[@]}" tar -xJf "$PATH_TMP_WORK/codex-primary-runtime.tar.xz" -C /opt/codex/runtimes

# Build the download URL for the matching official Node.js distribution.
NAME_NODE_DIST="node-${VERSION_NODE}-linux-x64"
URL_NODE_DIST="https://nodejs.org/dist/${VERSION_NODE}/${NAME_NODE_DIST}.tar.xz"

curl -fsSL "$URL_NODE_DIST" -o "$PATH_TMP_WORK/node.tar.xz"

PATH_NODE_ROOT="$PATH_CODEX_PRIMARY_RUNTIME/dependencies/node"

# Extract npm and Corepack directly into the bundled Node installation.
"${SUDO[@]}" tar -xJf "$PATH_TMP_WORK/node.tar.xz" \
    -C "$PATH_NODE_ROOT" \
    --strip-components=1 \
    "$NAME_NODE_DIST/lib/node_modules/npm" \
    "$NAME_NODE_DIST/lib/node_modules/corepack" \
    "$NAME_NODE_DIST/bin/npm" \
    "$NAME_NODE_DIST/bin/npx" \
    "$NAME_NODE_DIST/bin/corepack"

# Create the stable cache path Codex uses for the primary runtime.
ln -sfn "$PATH_CODEX_PRIMARY_RUNTIME" \
    "$PATH_CODEX_RUNTIMES_CACHE/codex-primary-runtime"

PATH_LIBREOFFICE_PROGRAM="$PATH_CODEX_PRIMARY_RUNTIME/dependencies/native/libreoffice-headless/libreoffice/program"

# Store LibreOffice's user profile in the normal per-user configuration directory.
"${SUDO[@]}" sed -i \
    's|^UserInstallation=.*$|UserInstallation=$SYSUSERCONFIG/libreoffice/4|' \
    "$PATH_LIBREOFFICE_PROGRAM/bootstraprc"

# Use the LibreOffice launcher when the environment supports its temporary-file needs,
# otherwise run soffice.bin directly.
cat > "$PATH_TMP_WORK/soffice" <<'EOF'
#!/bin/sh
set -eu

PATH_PROGRAM=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

LD_LIBRARY_PATH="${PATH_PROGRAM}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
SAL_ENABLE_FILE_LOCKING=1

export LD_LIBRARY_PATH
export SAL_ENABLE_FILE_LOCKING

if [ -r /proc/version ] && { [ -w /tmp ] || [ -w /var/tmp ]; }; then
    exec "$PATH_PROGRAM/soffice.libreoffice" "$@"
fi

exec "$PATH_PROGRAM/soffice.bin" "$@"
EOF

"${SUDO[@]}" install -m 0755 "$PATH_TMP_WORK/soffice" "$PATH_LIBREOFFICE_PROGRAM/soffice"

curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh

export PATH="${CODEX_INSTALL_DIR:-$HOME/.local/bin}:$PATH"

PATH_RUNTIME_MARKETPLACE="$PATH_CODEX_RUNTIMES_CACHE/codex-primary-runtime/plugins/openai-primary-runtime"
CONFIG_RUNTIME_MARKETPLACE_TYPE='marketplaces.openai-primary-runtime.source_type="local"'
CONFIG_RUNTIME_MARKETPLACE_SOURCE="marketplaces.openai-primary-runtime.source=\"$PATH_RUNTIME_MARKETPLACE\""

# Install the plugins provided by the Primary Runtime marketplace.
if [ -f "$PATH_RUNTIME_MARKETPLACE/.agents/plugins/marketplace.json" ]; then
    PLUGIN_IDS="$(
        codex \
            -c "$CONFIG_RUNTIME_MARKETPLACE_TYPE" \
            -c "$CONFIG_RUNTIME_MARKETPLACE_SOURCE" \
            plugin list \
            --marketplace openai-primary-runtime \
            --available \
            --json |
        python3 -c '
import json, sys

for plugin in json.load(sys.stdin).get("available", []):
    if plugin["installPolicy"] != "NOT_AVAILABLE":
        print(plugin["pluginId"])
'
    )"

    for PLUGIN_ID in $PLUGIN_IDS; do
        codex \
            -c "$CONFIG_RUNTIME_MARKETPLACE_TYPE" \
            -c "$CONFIG_RUNTIME_MARKETPLACE_SOURCE" \
            plugin add "$PLUGIN_ID"
    done
fi