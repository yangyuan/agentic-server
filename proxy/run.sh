#!/bin/sh
set -eu

EFFECTIVE_UID="$(id -u)"
EFFECTIVE_GID="$(id -g)"

run_privileged() {
	if [ "$EFFECTIVE_UID" -eq 0 ]; then
		"$@"
	else
		sudo "$@"
	fi
}

PATH_PROXY_RUNTIME="/opt/agentic/proxy"
HOST="0.0.0.0"
PORT="4500"
ACCESS_TOKEN=""
ACCESS_TOKEN_SET=false
SOCKET="~/.codex/app-server-control/app-server-control.sock"

while [ "$#" -gt 0 ]; do
	case "$1" in
		--host|--port|--access-token|--sock)
			if [ "$#" -lt 2 ]; then
				printf 'Missing value for %s\n' "$1" >&2
				exit 2
			fi
			case "$1" in
				--host) HOST="$2" ;;
				--port) PORT="$2" ;;
				--access-token)
					ACCESS_TOKEN="$2"
					ACCESS_TOKEN_SET=true
					;;
				--sock) SOCKET="$2" ;;
			esac
			shift 2
			;;
		-h|--help)
			printf 'Usage: sh run.sh [--host HOST] [--port PORT] [--access-token TOKEN] [--sock SOCKET]\n'
			exit 0
			;;
		*)
			printf 'Unknown option: %s\n' "$1" >&2
			exit 2
			;;
	esac
done

if [ ! -x "$PATH_PROXY_RUNTIME/.venv/bin/python" ] || [ ! -f "$PATH_PROXY_RUNTIME/proxy.py" ]; then
	printf 'Proxy is not installed; run setup.sh first.\n' >&2
	exit 1
fi

umask 077
PATH_TMP_WORK="$(mktemp -d)"
trap 'rm -rf "$PATH_TMP_WORK"' EXIT

"$PATH_PROXY_RUNTIME/.venv/bin/python" -c '
import json, sys
route = {"name": "local", "socket": sys.argv[4]}
if sys.argv[5] == "true":
    route["token"] = sys.argv[3]
config = {
    "proxy": {"host": sys.argv[1], "port": int(sys.argv[2])},
    "routes": [route],
}
print(json.dumps(config, indent=2))
' "$HOST" "$PORT" "$ACCESS_TOKEN" "$SOCKET" "$ACCESS_TOKEN_SET" > "$PATH_TMP_WORK/config.json"
run_privileged install -m 0600 -o "$EFFECTIVE_UID" -g "$EFFECTIVE_GID" \
	"$PATH_TMP_WORK/config.json" "$PATH_PROXY_RUNTIME/config.json.tmp"
run_privileged mv "$PATH_PROXY_RUNTIME/config.json.tmp" "$PATH_PROXY_RUNTIME/config.json"
rm -rf "$PATH_TMP_WORK"
trap - EXIT

exec "$PATH_PROXY_RUNTIME/.venv/bin/python" "$PATH_PROXY_RUNTIME/proxy.py" \
	--config-file "$PATH_PROXY_RUNTIME/config.json"
