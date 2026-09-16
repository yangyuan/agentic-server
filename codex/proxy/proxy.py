import argparse
import asyncio
import os
from http import HTTPStatus
from urllib.parse import parse_qs, urlsplit

from websockets.asyncio.client import connect, unix_connect
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

ROUTES = {
    "access-token": "~/.codex/app-server-control/app-server-control.sock",
}


CODEX_RESPONSE_MAX_SIZE = 128 << 20  # 134,217,728 bytes

async def auth(connection, request):
    query = parse_qs(urlsplit(request.path).query)
    token = query.get("token", [None])[0]

    if token not in ROUTES:
        return connection.respond(HTTPStatus.UNAUTHORIZED, "Unauthorized\n")


async def pipe(src, dst):
    try:
        async for msg in src:
            await dst.send(msg)
    except ConnectionClosed:
        pass
    finally:
        await dst.close()


async def handler(client_ws):
    query = parse_qs(urlsplit(client_ws.request.path).query)
    token = query.get("token", [None])[0]
    target = ROUTES.get(token)

    if target is None:
        await client_ws.close(1008, "Unauthorized")
        return

    if target.startswith(("ws://", "wss://")):
        upstream = connect(
            target,
            compression=None,
            proxy=None,
            ping_interval=None,
            max_size=CODEX_RESPONSE_MAX_SIZE,
        )
    else:
        upstream = unix_connect(
            path=os.path.expanduser(target),
            uri="ws://localhost/",
            compression=None,
            proxy=None,
            ping_interval=None,
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
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=4500)
    args = parser.parse_args()

    async with serve(
        handler,
        args.host,
        args.port,
        process_request=auth,
        ping_interval=None,
        max_size=CODEX_RESPONSE_MAX_SIZE,
    ):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())