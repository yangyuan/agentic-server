#!/bin/sh
set -e

PATH_CODEX_PRIMARY_RUNTIME="/opt/codex/runtimes/codex-primary-runtime"
PATH_NODE_ROOT="$PATH_CODEX_PRIMARY_RUNTIME/dependencies/node"

export PATH="$PATH_CODEX_PRIMARY_RUNTIME/dependencies/bin/override:$PATH_CODEX_PRIMARY_RUNTIME/dependencies/python/bin:$PATH_NODE_ROOT/bin:$PATH_CODEX_PRIMARY_RUNTIME/dependencies/bin:${CODEX_INSTALL_DIR:-$HOME/.local/bin}:$PATH:$PATH_CODEX_PRIMARY_RUNTIME/dependencies/bin/fallback"

URL_LISTEN="unix://"
FULL_ACCESS=false

while [ "$#" -gt 0 ]; do
	case "$1" in
		--listen)
			URL_LISTEN="$2"
			shift
			;;
		--full-access)
			FULL_ACCESS=true
			;;
	esac
	shift
done

set -- app-server --listen "$URL_LISTEN" --remote-control
if [ "$FULL_ACCESS" = true ]; then
	set -- -c 'sandbox_mode="danger-full-access"' "$@"
fi

codex "$@" &
