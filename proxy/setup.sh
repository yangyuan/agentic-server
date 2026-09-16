#!/bin/sh
set -eu

EFFECTIVE_UID="$(id -u)"

run_privileged() {
	if [ "$EFFECTIVE_UID" -eq 0 ]; then
		"$@"
	else
		sudo "$@"
	fi
}

PATH_PROXY_RUNTIME="/opt/agentic/proxy"
PATH_PROXY_SOURCE="$(dirname -- "$0")/proxy.py"
URL_PROXY="https://raw.githubusercontent.com/yangyuan/agentic-server/master/proxy/proxy.py"
packages=""

if ! command -v python3 >/dev/null 2>&1; then
	packages="$packages python3 python3-venv"
elif ! python3 -c 'import venv, ensurepip' >/dev/null 2>&1; then
	packages="$packages python3-venv"
fi

if [ -n "$packages" ]; then
	run_privileged apt-get update
	run_privileged apt-get install -y --no-install-recommends $packages
	run_privileged rm -rf /var/lib/apt/lists/*
fi

if [ ! -x "$PATH_PROXY_RUNTIME/.venv/bin/python" ]; then
	run_privileged "$(command -v python3)" -m venv "$PATH_PROXY_RUNTIME/.venv"
fi

if ! "$PATH_PROXY_RUNTIME/.venv/bin/python" -c 'from websockets.asyncio.client import connect, unix_connect' >/dev/null 2>&1; then
	run_privileged "$PATH_PROXY_RUNTIME/.venv/bin/python" -m pip install --no-cache-dir websockets
fi

umask 077
PATH_TMP_WORK="$(mktemp -d)"
trap 'rm -rf "$PATH_TMP_WORK"' EXIT

if [ -f "$0" ] && [ -f "$PATH_PROXY_SOURCE" ] &&
	[ "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)" != "$PATH_PROXY_RUNTIME" ]; then
	cp "$PATH_PROXY_SOURCE" "$PATH_TMP_WORK/proxy.py"
else
	curl -fsSL "$URL_PROXY" -o "$PATH_TMP_WORK/proxy.py"
fi
run_privileged install -m 0644 "$PATH_TMP_WORK/proxy.py" "$PATH_PROXY_RUNTIME/proxy.py.tmp"
run_privileged mv "$PATH_PROXY_RUNTIME/proxy.py.tmp" "$PATH_PROXY_RUNTIME/proxy.py"
