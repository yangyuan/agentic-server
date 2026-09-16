PATH_PROXY_RUNTIME="/opt/proxy"

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

cp "$(dirname -- "$0")/proxy.py" "$PATH_PROXY_RUNTIME/proxy.py"

"$PATH_PROXY_RUNTIME/.venv/bin/python" "$PATH_PROXY_RUNTIME/proxy.py" "$@" &