# Codex App Server

For a standard Codex installation, use the official installer:

```sh
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

Start app-server:

```sh
# Start app-server with a Unix socket
codex app-server --listen unix://

# Or listen on a WebSocket
codex app-server --listen ws://127.0.0.1:4500

# You can also enable ChatGPT remote control with --remote-control, not conflicting with --listen.
codex app-server --listen ws://127.0.0.1:4500 --remote-control
```

For advanced agent workflows, we recommend our setup script. It installs official Codex with supporting official runtimes, tools, and plugins, and is optimized for container deployments.

## Setup

Requires Linux x64, a POSIX shell (`sh`), `curl`, `tar`, `xz`, and `python3`.

On Ubuntu 24.04, [Ubuntu setup](ubuntu/setup.sh) installs prerequisites and extra tools:

```sh
# All packages (default)
curl -fsSL https://raw.githubusercontent.com/yangyuan/agentic-server/master/codex/ubuntu/setup.sh | sh

# Prerequisites only
curl -fsSL https://raw.githubusercontent.com/yangyuan/agentic-server/master/codex/ubuntu/setup.sh | sh -s -- --essential
```

Then install Codex and its supporting runtime:

```sh
curl -fsSL https://raw.githubusercontent.com/yangyuan/agentic-server/master/codex/app-server/setup.sh | sh
```

Installs the runtime under `/opt/codex` and links it at `~/.cache/codex-runtimes/codex-primary-runtime`. Codex and plugins are installed for the current account. Setup detects root automatically and uses `sudo` for `/opt/codex` writes only when needed.

To install for root:

```sh
curl -fsSL https://raw.githubusercontent.com/yangyuan/agentic-server/master/codex/app-server/setup.sh | sudo -H sh
```

In containers already running as root, omit `sudo -H`.

## Run App Server

Starts app-server in the background with the runtime environment and remote control enabled. Use the same account as setup.

```sh
curl -fsSL https://raw.githubusercontent.com/yangyuan/agentic-server/master/codex/app-server/run.sh | sh
```

`--listen URL` changes the listener (default: `unix://`). `--full-access` disables sandboxing without changing the approval policy.

```sh
curl -fsSL https://raw.githubusercontent.com/yangyuan/agentic-server/master/codex/app-server/run.sh | sh -s -- --listen ws://127.0.0.1:4500 --full-access
```

## Authentication Proxy

Do not expose an unauthenticated app-server WebSocket endpoint to untrusted networks. Keep the app-server on localhost or a private container network.

We provide a simple [proxy.py](../proxy/proxy.py) that checks each client's configured access token before forwarding its connection to a Unix socket or WebSocket upstream. Use a non-empty token when exposing the proxy, and use TLS (`wss://`) or a private encrypted network for remote access.

[setup.sh](../proxy/setup.sh) installs missing Python dependencies, creates the virtual environment, and downloads the latest Python script into `/opt/agentic/proxy`. On Debian/Ubuntu, it automatically uses `sudo` for system packages and `/opt` writes when needed. It does not change configuration or start the proxy. Rerunning setup reuses installed dependencies and refreshes the Python script:

```sh
curl -fsSL https://raw.githubusercontent.com/yangyuan/agentic-server/master/proxy/setup.sh | sh
```

[run.sh](../proxy/run.sh) writes `/opt/agentic/proxy/config.json` from its options and starts the installed proxy in the background. It automatically uses `sudo` for config installation when needed; the proxy itself runs as your account:

```sh
curl -fsSL https://raw.githubusercontent.com/yangyuan/agentic-server/master/proxy/run.sh | sh -s -- --host 127.0.0.1 --port 4500 --token token \
	--sock '~/.codex/app-server-control/app-server-control.sock'
```

All four options are optional. Defaults are host `0.0.0.0`, port `4500`, no authentication, and socket `~/.codex/app-server-control/app-server-control.sock`. Use `--host 127.0.0.1` for local-only access. Omitting `--token` omits the route's token field; passing `--token ""` requires an explicit empty query token (`?token=`).

Stop the running proxy before rerunning the launcher on the same port. Each launch rewrites the generated config; it does not reinstall dependencies or refresh the Python script.

To use an existing configuration, start the installed Python proxy directly:

```sh
/opt/agentic/proxy/.venv/bin/python /opt/agentic/proxy/proxy.py --config-file /path/to/config.json
```

A configuration defines the listener in `proxy.host` and `proxy.port`, and a `routes` array of objects with `name`, `socket`, and an optional `token`:

```json
{
	"proxy": {"host": "127.0.0.1", "port": 4500},
	"routes": [
		{"name": "local", "token": "secret", "socket": "~/.codex/app-server-control/app-server-control.sock"}
	]
}
```

Route authentication:

- `"token": "secret"` requires `?token=secret`.
- `"token": ""` requires an explicit empty token (`?token=`); omitting the query parameter does not match.
- Omitting the `token` field allows requests without a token query parameter. This does not bypass authentication for other routes.

Duplicate tokens, including duplicate empty strings, cause startup to fail. Only one route may omit `token`, so requests without a token have one destination. Unknown tokens receive HTTP 401. `"token": null` is invalid. Replace example tokens with long random secrets before deployment; keep unauthenticated routes on localhost or a trusted private network.

The Docker image installs the proxy during its build and starts Python directly with [config.json](../docker/config.json) mounted read-only at `/opt/agentic/proxy/config.json`. Restart the proxy after changing configuration, and keep the published container port aligned with `proxy.port`. Tokens passed on the command line may be visible in shell history and process listings; prefer a restricted configuration file in production.

Socket paths starting with `~` use the proxy process's home directory; use an absolute path for a socket owned by another account.
