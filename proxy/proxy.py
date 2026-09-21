import argparse
import asyncio
import json
import os
from functools import partial
from http import HTTPStatus
from urllib.parse import parse_qs, urlsplit

from websockets.asyncio.client import connect, unix_connect
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

CODEX_RESPONSE_MAX_SIZE = 128 << 20  # 134,217,728 bytes

async def auth(connection, request, routes):
    query = parse_qs(urlsplit(request.path).query, keep_blank_values=True)
    token = query.get("token", [None])[0]

    if token not in routes:
        return connection.respond(HTTPStatus.UNAUTHORIZED, "Unauthorized\n")


async def pipe(src, dst):
    try:
        async for msg in src:
            await dst.send(msg)
    except ConnectionClosed:
        pass
    finally:
        await dst.close()


async def handler(client_ws, routes):
    query = parse_qs(urlsplit(client_ws.request.path).query, keep_blank_values=True)
    token = query.get("token", [None])[0]
    target = routes.get(token)

    if target is None:
        await client_ws.close(1008, "Unauthorized")
        return

    if target.startswith(("ws://", "wss://")):
        upstream = connect(
            target,
            compression=None,
            proxy=None,
            max_size=CODEX_RESPONSE_MAX_SIZE,
        )
    else:
        upstream = unix_connect(
            path=os.path.expanduser(target),
            uri="ws://localhost/",
            compression=None,
            proxy=None,
            max_size=CODEX_RESPONSE_MAX_SIZE,
        )

    try:
        async with upstream as codex_ws:
            await asyncio.gather(
                pipe(client_ws, codex_ws),
                pipe(codex_ws, client_ws),
            )
    except ConnectionClosed:
        pass
    except OSError:
        await client_ws.close(1011, "Upstream unavailable")


async def main():
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--config-file", required=True, metavar="PATH", help="Read JSON configuration from a file")
    args = parser.parse_args()

    try:
        with open(os.path.expanduser(args.config_file), encoding="utf-8") as config_file:
            config = json.load(config_file)
    except (OSError, ValueError) as error:
        parser.error(f"Cannot load configuration: {error}")

    if not isinstance(config, dict) or not isinstance(config.get("routes"), list):
        parser.error("Configuration must be an object with a routes array")

    proxy_config = config.get("proxy")
    if (
        not isinstance(proxy_config, dict)
        or not isinstance(proxy_config.get("host"), str)
        or not proxy_config["host"].strip()
    ):
        parser.error("Configuration must contain a proxy object with a non-empty host string")
    if type(proxy_config.get("port")) is not int or not 0 <= proxy_config["port"] <= 65535:
        parser.error("Proxy port must be an integer between 0 and 65535")

    routes = {}
    for route in config["routes"]:
        if not isinstance(route, dict) or not all(
            isinstance(route.get(field), str) for field in ("name", "socket")
        ):
            parser.error("Each route must contain name and socket strings")
        if not route["name"].strip() or not route["socket"].strip():
            parser.error("Route name and socket must not be empty")
        if "token" in route and not isinstance(route["token"], str):
            parser.error("Route token must be a string when provided")
        token = route.get("token")
        if token in routes:
            if token is None:
                parser.error("Only one route may omit token")
            parser.error("Route tokens must be unique")
        routes[token] = route["socket"]

    async with serve(
        partial(handler, routes=routes),
        proxy_config["host"],
        proxy_config["port"],
        process_request=partial(auth, routes=routes),
        max_size=CODEX_RESPONSE_MAX_SIZE,
    ):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())