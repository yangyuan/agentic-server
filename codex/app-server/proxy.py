import argparse
import asyncio
import os
from functools import partial
from urllib.parse import urlsplit, parse_qs

import websockets
from websockets.exceptions import ConnectionClosed
from websockets.http11 import Response
from websockets.datastructures import Headers

ACCESS_TOKEN = "9527"
CODEX_RESPONSE_MAX_SIZE = 128 << 20  # 134,217,728 bytes

async def auth(connection, request):
    query = parse_qs(urlsplit(request.path).query)
    token = query.get("token", [None])[0]

    if token != ACCESS_TOKEN:
        return Response(
            401,
            "Unauthorized",
            Headers(),
            b"Unauthorized\n",
        )


async def pipe(src, dst):
    try:
        async for msg in src:
            await dst.send(msg)
    except ConnectionClosed:
        pass


async def handler(client_ws, target):
    if target.startswith(("ws://", "wss://")):
        connect = websockets.connect(
            target,
            compression=None,
            proxy=None,
            ping_interval=None,
            max_size=CODEX_RESPONSE_MAX_SIZE,
        )
    else:
        connect = websockets.unix_connect(
            path=os.path.expanduser(target),
            uri="ws://localhost/",
            compression=None,
            proxy=None,
            ping_interval=None,
            max_size=CODEX_RESPONSE_MAX_SIZE,
        )

    try:
        async with connect as codex_ws:
            await asyncio.gather(
                pipe(client_ws, codex_ws),
                pipe(codex_ws, client_ws),
            )
    except ConnectionClosed:
        pass


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--target", default="~/.codex/app-server-control/app-server-control.sock"
    )
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=4500)
    args = parser.parse_args()

    async with websockets.serve(
        partial(handler, target=args.target),
        args.host,
        args.port,
        process_request=auth,
        ping_interval=None,
        max_size=CODEX_RESPONSE_MAX_SIZE,
    ):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())