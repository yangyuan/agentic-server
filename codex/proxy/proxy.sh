#!/bin/sh
set -eu

PATH_PROXY_RUNTIME="/opt/proxy"
PATH_PROXY_SOURCE="$(dirname -- "$0")/proxy.py"
URL_PROXY="https://raw.githubusercontent.com/yangyuan/agentic-server/master/codex/proxy/proxy.py"
packages=""

if ! command -v python3 >/dev/null 2>&1; then
	packages="$packages python3 python3-venv"
elif ! python3 -c 'import venv, ensurepip' >/dev/null 2>&1; then
	packages="$packages python3-venv"
fi

if [ -n "$packages" ]; then
	apt-get update
	apt-get install -y --no-install-recommends $packages
	rm -rf /var/lib/apt/lists/*
fi

if [ ! -x "$PATH_PROXY_RUNTIME/.venv/bin/python" ]; then
	python3 -m venv "$PATH_PROXY_RUNTIME/.venv"
	"$PATH_PROXY_RUNTIME/.venv/bin/python" -m pip install --no-cache-dir websockets
fi

if [ -f "$0" ] && [ -f "$PATH_PROXY_SOURCE" ]; then
	cp "$PATH_PROXY_SOURCE" "$PATH_PROXY_RUNTIME/proxy.py"
elif [ ! -f "$PATH_PROXY_RUNTIME/proxy.py" ]; then
	curl -fsSL "$URL_PROXY" -o "$PATH_PROXY_RUNTIME/proxy.py.tmp"
	mv "$PATH_PROXY_RUNTIME/proxy.py.tmp" "$PATH_PROXY_RUNTIME/proxy.py"
fi

"$PATH_PROXY_RUNTIME/.venv/bin/python" "$PATH_PROXY_RUNTIME/proxy.py" "$@" &