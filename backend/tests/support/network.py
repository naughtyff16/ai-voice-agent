"""In-process network doubles for failure tests.

``TcpProxy`` relays a loopback port to a real server and can cut every
connection and stop listening (the server "disappears" from the network) and
later listen again on the same port. ``FakeRespServer`` speaks just enough of
the Redis protocol for redis-py's connection handshake and answers PING with a
scripted reply, including malformed ones and none at all.

Both run on the test's own event loop and bind 127.0.0.1 only.
"""

from __future__ import annotations

import asyncio
import contextlib
from typing import Final

from tests.support.infrastructure import HOST

_CHUNK: Final = 65_536


class TcpProxy:
    def __init__(self, target_port: int) -> None:
        self._target_port = target_port
        self._server: asyncio.Server | None = None
        self._writers: set[asyncio.StreamWriter] = set()
        self._pumps: set[asyncio.Task[None]] = set()
        self.port = 0

    @property
    def is_listening(self) -> bool:
        return self._server is not None

    async def start(self) -> None:
        """Listen, on the previous port if there was one."""
        self._server = await asyncio.start_server(self._accept, HOST, self.port)
        self.port = self._server.sockets[0].getsockname()[1]

    async def _accept(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            upstream_reader, upstream_writer = await asyncio.open_connection(
                HOST, self._target_port
            )
        except OSError:
            writer.transport.abort()
            return
        self._writers.update({writer, upstream_writer})
        for source, sink in ((reader, upstream_writer), (upstream_reader, writer)):
            task = asyncio.create_task(self._pump(source, sink))
            self._pumps.add(task)
            task.add_done_callback(self._pumps.discard)

    async def _pump(self, source: asyncio.StreamReader, sink: asyncio.StreamWriter) -> None:
        try:
            while data := await source.read(_CHUNK):
                sink.write(data)
                await sink.drain()
        except OSError:
            pass
        finally:
            sink.transport.abort()
            self._writers.discard(sink)

    async def cut(self) -> None:
        """Reset every relayed connection and stop listening: new connects are refused."""
        server, self._server = self._server, None
        if server is not None:
            server.close()
        for writer in list(self._writers):
            writer.transport.abort()
        self._writers.clear()
        if self._pumps:
            await asyncio.gather(*self._pumps, return_exceptions=True)
        if server is not None:
            await server.wait_closed()

    async def close(self) -> None:
        await self.cut()


async def _read_command(reader: asyncio.StreamReader) -> list[bytes] | None:
    line = await reader.readline()
    if not line:
        return None
    if not line.startswith(b"*"):
        return line.split()
    arguments = []
    for _ in range(int(line[1:])):
        length_line = await reader.readline()
        data = await reader.readexactly(int(length_line[1:]) + 2)
        arguments.append(data[:-2])
    return arguments


class FakeRespServer:
    """``ping_reply`` is sent verbatim for PING; ``None`` means never answer it."""

    def __init__(self, ping_reply: bytes | None) -> None:
        self.ping_reply = ping_reply
        self._server: asyncio.Server | None = None
        self._writers: set[asyncio.StreamWriter] = set()
        self._closed = asyncio.Event()
        self.port = 0
        self.pings = 0

    @property
    def url(self) -> str:
        return f"redis://{HOST}:{self.port}/0"

    async def start(self) -> None:
        self._server = await asyncio.start_server(self._handle, HOST, 0)
        self.port = self._server.sockets[0].getsockname()[1]

    async def _handle(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        self._writers.add(writer)
        try:
            while (command := await _read_command(reader)) is not None:
                name = command[0].upper() if command else b""
                if name == b"PING":
                    self.pings += 1
                    if self.ping_reply is None:
                        await self._closed.wait()
                        return
                    writer.write(self.ping_reply)
                elif name == b"INFO":
                    body = b"redis_version:7.2.4\r\n"
                    writer.write(b"$%d\r\n%s\r\n" % (len(body), body))
                else:
                    # CLIENT SETNAME / SETINFO and anything else of the handshake.
                    writer.write(b"+OK\r\n")
                await writer.drain()
        except (OSError, asyncio.IncompleteReadError, ValueError):
            pass
        finally:
            self._writers.discard(writer)
            writer.transport.abort()

    async def close(self) -> None:
        self._closed.set()
        if self._server is not None:
            self._server.close()
        for writer in list(self._writers):
            writer.transport.abort()
        if self._server is not None:
            with contextlib.suppress(OSError):
                await self._server.wait_closed()
