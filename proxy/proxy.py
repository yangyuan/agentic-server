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
STREAM_MESSAGE_MAX_SIZE = 16 << 20

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


async def websocket_to_stream(websocket, writer):
    async for message in websocket:
        if not isinstance(message, str):
            await websocket.close(1003, "Text messages required")
            return
        data = message.encode("utf-8")
        if len(data) > STREAM_MESSAGE_MAX_SIZE:
            await websocket.close(1009, "Message too large")
            return
        if b"\n" in data or b"\r" in data:
            await websocket.close(1007, "Messages must be a single line")
            return
        writer.write(data + b"\n")
        await writer.drain()


async def stream_to_websocket(reader, websocket):
    while line := await reader.readline():
        if not line.endswith(b"\n"):
            raise ValueError("Incomplete upstream message")
        if payload := line.rstrip(b"\r\n"):
            await websocket.send(payload.decode("utf-8"))


async def websocket_to_stream_raw(websocket, writer):
    async for message in websocket:
        writer.write(message.encode("utf-8") if isinstance(message, str) else message)
        await writer.drain()


async def stream_to_websocket_raw(reader, websocket):
    while chunk := await reader.read(65536):
        await websocket.send(chunk)


async def bridge_stream(client_ws, route):
    process = None
    writer = None
    tasks = []
    try:
        if route["type"] == "stdio":
            cwd = route.get("cwd")
            process = await asyncio.create_subprocess_exec(
                os.path.expanduser(route["command"]),
                *route.get("args", []),
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                cwd=os.path.expanduser(cwd) if cwd is not None else None,
                limit=STREAM_MESSAGE_MAX_SIZE,
            )
            reader, writer = process.stdout, process.stdin
        else:
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(route["host"], route["port"], limit=STREAM_MESSAGE_MAX_SIZE),
                timeout=10,
            )
        if route.get("framing") == "none":
            to_stream, to_websocket = websocket_to_stream_raw, stream_to_websocket_raw
        else:
            to_stream, to_websocket = websocket_to_stream, stream_to_websocket
        tasks = [
            asyncio.create_task(to_stream(client_ws, writer)),
            asyncio.create_task(to_websocket(reader, client_ws)),
            asyncio.create_task(client_ws.wait_closed()),
        ]
        done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for task in done:
            task.result()
    except ConnectionClosed:
        pass
    except (OSError, ValueError, UnicodeError, asyncio.TimeoutError):
        await client_ws.close(1011, "Upstream unavailable or invalid")
    finally:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        if writer is not None:
            writer.close()
            try:
                await asyncio.wait_for(writer.wait_closed(), timeout=2)
            except (OSError, asyncio.TimeoutError):
                pass
        if process is not None:
            try:
                await asyncio.wait_for(process.wait(), timeout=3)
            except asyncio.TimeoutError:
                try:
                    process.terminate()
                except ProcessLookupError:
                    pass
                try:
                    await asyncio.wait_for(process.wait(), timeout=3)
                except asyncio.TimeoutError:
                    try:
                        process.kill()
                    except ProcessLookupError:
                        pass
                    await process.wait()
        await client_ws.close()


async def handler(client_ws, routes):
    query = parse_qs(urlsplit(client_ws.request.path).query, keep_blank_values=True)
    token = query.get("token", [None])[0]
    route = routes.get(token)

    if route is None:
        await client_ws.close(1008, "Unauthorized")
        return

    if route["type"] != "socket":
        await bridge_stream(client_ws, route)
        return

    target = route["socket"]
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
        if not isinstance(route, dict) or not isinstance(route.get("name"), str) or not route["name"].strip():
            parser.error("Each route must contain a non-empty name string")
        if "token" in route and not isinstance(route["token"], str):
            parser.error("Route token must be a string when provided")
        token = route.get("token")
        if token in routes:
            if token is None:
                parser.error("Only one route may omit token")
            parser.error("Route tokens must be unique")
        route_type = route.get("type", "socket")
        if route_type == "socket":
            if not isinstance(route.get("socket"), str) or not route["socket"].strip():
                parser.error("socket routes require a non-empty socket string")
            if "framing" in route:
                parser.error("socket routes do not support framing")
        elif route_type == "stdio":
            if not isinstance(route.get("command"), str) or not route["command"].strip():
                parser.error("stdio routes require a non-empty command string")
            arguments = route.get("args", [])
            if not isinstance(arguments, list) or not all(isinstance(argument, str) for argument in arguments):
                parser.error("stdio args must be an array of strings")
            cwd = route.get("cwd")
            if cwd is not None and (not isinstance(cwd, str) or not cwd.strip()):
                parser.error("stdio cwd must be a non-empty string when provided")
        elif route_type == "tcp":
            if not isinstance(route.get("host"), str) or not route["host"].strip():
                parser.error("tcp routes require a non-empty host string")
            if type(route.get("port")) is not int or not 1 <= route["port"] <= 65535:
                parser.error("tcp port must be an integer between 1 and 65535")
        else:
            parser.error("Route type must be socket, stdio, or tcp")
        if route.get("framing", "line") not in ("line", "none"):
            parser.error("Route framing must be line or none")
        routes[token] = {**route, "type": route_type}

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