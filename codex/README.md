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
codex app-server --listen ws://127.0.0.1:4501

# You can also enable ChatGPT remote control with --remote-control, not conflicting with --listen.
codex app-server --listen ws://0.0.0.0:4501 --remote-control
```

For advanced agent workflows, we recommend our setup script. It installs official Codex with supporting official runtimes, tools, and plugins, and is optimized for container deployments.

## Setup

Requires Linux x64, a POSIX shell (`sh`), `curl`, `tar`, `xz`, and `python3`.

```sh
sh setup.sh
```

```sh
curl -fsSL https://raw.githubusercontent.com/yangyuan/agentic-server/master/codex/app-server/setup.sh | sh
```

Installs the runtime under `/opt/codex` and links it at `~/.cache/codex-runtimes/codex-primary-runtime`. Codex and plugins are installed for your account; only `/opt/codex` writes require sudo.

To install for root:

```sh
sudo -H sh setup.sh --root
```

```sh
curl -fsSL https://raw.githubusercontent.com/yangyuan/agentic-server/master/codex/app-server/setup.sh | sudo -H sh -s -- --root
```

In containers already running as root, omit `sudo -H`.

## Run App Server

Starts app-server in the background with the runtime environment and remote control enabled. Use the same account as setup.

```sh
sh run.sh
```

```sh
curl -fsSL https://raw.githubusercontent.com/yangyuan/agentic-server/master/codex/app-server/run.sh | sh
```

`--listen URL` changes the listener (default: `unix://`). `--full-access` disables sandboxing without changing the approval policy.

```sh
sh run.sh --listen ws://127.0.0.1:4501 --full-access
```

```sh
curl -fsSL https://raw.githubusercontent.com/yangyuan/agentic-server/master/codex/app-server/run.sh | sh -s -- --listen ws://127.0.0.1:4501 --full-access
```

## Authentication Proxy

Do not expose an unauthenticated app-server WebSocket endpoint to untrusted networks. Keep the app-server on localhost or a private container network.

We provide a simple [proxy.py](proxy/proxy.py) that checks each client's access token before forwarding its connection to the configured Unix socket or WebSocket upstream. Expose the proxy instead of the app-server, and use TLS (`wss://`) or a private encrypted network for remote access.

[proxy.sh](proxy/proxy.sh) installs dependencies and starts the proxy in the background. Run as root on Debian/Ubuntu:

```sh
sh proxy/proxy.sh --host 127.0.0.1 --port 4500
```

Or install without cloning the repository:

```sh
curl -fsSL https://raw.githubusercontent.com/yangyuan/agentic-server/master/codex/proxy/proxy.sh | sh -s -- --host 127.0.0.1 --port 4500
```

From a non-root account, use `sudo -H sh` instead of `sh`. The piped installer downloads the Python script to `/opt/proxy/proxy.py` only if it is absent, preserving existing customizations. Local installation copies the adjacent Python script instead.

Configure access tokens and their upstream targets in the `ROUTES` dictionary. Clients authenticate with `?token=<TOKEN>`, where `TOKEN` is a key in `ROUTES`. Replace the example tokens before exposing the proxy.

For a piped installation, edit `/opt/proxy/proxy.py`. Socket paths starting with `~` use the proxy process's home directory; use an absolute path for a socket owned by another account.

Use `--host` and `--port` to set the listening address and port. Defaults are `0.0.0.0` and `4500`; the example above limits access to the local machine.
