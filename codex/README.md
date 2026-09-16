# Codex App Server

For a standard Codex installation, use the official installer:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

For advanced agent workflows, we recommend our setup script. It installs Codex with supporting runtimes, tools, and plugins, and is optimized for Docker deployments.

## Setup

Requires Linux x64, Bash, `curl`, `tar`, `xz`, and `python3`.

```bash
bash setup.sh
```

```bash
curl -fsSL https://raw.githubusercontent.com/yangyuan/agentic-server/master/codex/app-server/setup.sh | bash
```

Installs the runtime under `/opt/codex` and links it at `~/.cache/codex-runtimes/codex-primary-runtime`. Codex and plugins are installed for your account; only `/opt/codex` writes require sudo.

To install for root:

```bash
sudo -H bash setup.sh --root
```

```bash
curl -fsSL https://raw.githubusercontent.com/yangyuan/agentic-server/master/codex/app-server/setup.sh | sudo -H bash -s -- --root
```

In containers already running as root, omit `sudo -H`.

## Run App Server

Starts app-server in the background with the runtime environment and remote control enabled. Use the same account as setup.

```bash
bash run.sh
```

```bash
curl -fsSL https://raw.githubusercontent.com/yangyuan/agentic-server/master/codex/app-server/run.sh | bash
```

`--listen URL` changes the listener (default: `unix://`). `--full-access` disables sandboxing without changing the approval policy.

```bash
bash run.sh --listen ws://127.0.0.1:4501 --full-access
```

```bash
curl -fsSL https://raw.githubusercontent.com/yangyuan/agentic-server/master/codex/app-server/run.sh | bash -s -- --listen ws://127.0.0.1:4501 --full-access
```

## Proxy Example (Optional)

[proxy.py](proxy/proxy.py) demonstrates token authentication in front of Unix socket or WebSocket upstreams. It is reference code, not a production proxy; use authentication and TLS appropriate to your deployment.

[proxy.sh](proxy/proxy.sh) installs dependencies and starts the example in the background:

```bash
bash proxy/proxy.sh --host 127.0.0.1 --port 4500
```

Configure access tokens and their upstream targets in the `ROUTES` dictionary. Clients authenticate with `?token=<TOKEN>`, where `TOKEN` is a key in `ROUTES`. Replace the example tokens before exposing the proxy.

Use `--host` and `--port` to set the listening address and port. Defaults are `0.0.0.0` and `4500`; the example above limits access to the local machine.
