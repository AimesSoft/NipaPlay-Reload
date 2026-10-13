#!/usr/bin/env python3
"""User-owned reverse TCP forwarding over a Mac-initiated SSH stdio channel.

WSL NAT need not reach a Windows/Mac listener. This forwards bytes, including
end-to-end mesh TLS. One invocation forwards one explicitly chosen port.
"""
import argparse
import asyncio
import os
from pathlib import Path
import socket
import struct
import sys

OPEN, DATA, CLOSE = 0, 1, 2
MAX_FRAME, MAX_CONNECTIONS = 65536, 64

class Hub:
    def __init__(self, reader, writer, target=None):
        self.reader, self.writer, self.target = reader, writer, target
        self.channels, self.tasks = {}, set()
        self.lock = asyncio.Lock()
        self.sequence = 0
        self.closed = False
    async def send(self, channel, operation, payload=b''):
        async with self.lock:
            self.writer.write(struct.pack('>IBI', channel, operation, len(payload)) + payload)
            await self.writer.drain()
    def track(self, coroutine):
        task = asyncio.create_task(coroutine)
        self.tasks.add(task)
        task.add_done_callback(self.tasks.discard)
    async def accepted(self, reader, writer):
        if len(self.channels) >= MAX_CONNECTIONS:
            writer.close(); return
        self.sequence += 1
        channel = self.sequence
        self.channels[channel] = writer
        await self.send(channel, OPEN)
        self.track(self.pump(channel, reader))
    async def pump(self, channel, reader):
        try:
            while payload := await reader.read(MAX_FRAME):
                await self.send(channel, DATA, payload)
        except (ConnectionError, OSError):
            pass  # The TCP connection has ended; report that channel's EOF.
        finally:
            writer = self.channels.pop(channel, None)
            if writer: writer.close()
            if not self.closed:
                try: await self.send(channel, CLOSE)
                except (ConnectionError, BrokenPipeError): self.closed = True
    async def run(self):
        try:
            while True:
                try: header = await self.reader.readexactly(9)
                except asyncio.IncompleteReadError: return
                channel, operation, size = struct.unpack('>IBI', header)
                if size > MAX_FRAME or operation not in (OPEN, DATA, CLOSE):
                    raise ValueError('invalid forwarding frame')
                payload = await self.reader.readexactly(size)
                if operation == OPEN:
                    if self.target is None or size or channel in self.channels or len(self.channels) >= MAX_CONNECTIONS:
                        raise ValueError('invalid forwarding channel')
                    try: reader, writer = await asyncio.open_connection('127.0.0.1', self.target)
                    except OSError:
                        await self.send(channel, CLOSE); continue
                    self.channels[channel] = writer
                    self.track(self.pump(channel, reader))
                elif operation == CLOSE:
                    writer = self.channels.pop(channel, None)
                    if writer: writer.close()
                elif (writer := self.channels.get(channel)) is not None:
                    writer.write(payload)
                    await writer.drain()
        finally:
            self.closed = True
            for writer in self.channels.values(): writer.close()
            for task in list(self.tasks): task.cancel()
            await asyncio.gather(*self.tasks, return_exceptions=True)

class StdoutWriter:
    def __init__(self): self.pending = b''
    def write(self, payload): self.pending = payload
    async def drain(self):
        payload = self.pending
        def write():
            view = memoryview(payload)
            while view: view = view[os.write(sys.stdout.fileno(), view):]
        await asyncio.to_thread(write)

async def listen_stdio(port):
    reader = asyncio.StreamReader()
    await asyncio.get_running_loop().connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin.buffer)
    hub = Hub(reader, StdoutWriter())
    server = await asyncio.start_server(hub.accepted, '127.0.0.1', port)
    print(f'forward listener 127.0.0.1:{port}', file=sys.stderr, flush=True)
    async with server: await hub.run()

async def forward(args):
    remote = ['wsl.exe', '--', 'python3', '-u', args.remote_script, '--stdio-listen', str(args.listen_port)]
    child = await asyncio.create_subprocess_exec('ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15',
        'workstation-wsl', *remote, stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE)
    print(f'forward PID {os.getpid()}; SSH PID {child.pid}; WSL loopback {args.listen_port} -> Mac loopback {args.target_port}', file=sys.stderr, flush=True)
    try: await Hub(child.stdout, child.stdin, args.target_port).run()
    finally:
        if child.returncode is None:
            child.terminate()
        await child.wait()

async def local_check():
    async def echo(reader, writer):
        try:
            while payload := await reader.read(4096): writer.write(payload); await writer.drain()
        finally: writer.close()
    server = await asyncio.start_server(echo, '127.0.0.1', 0)
    target = server.sockets[0].getsockname()[1]
    with socket.socket() as lease: lease.bind(('127.0.0.1', 0)); port = lease.getsockname()[1]
    child = await asyncio.create_subprocess_exec(sys.executable, str(Path(__file__).resolve()), '--stdio-listen', str(port),
        stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    assert (await child.stderr.readline()).decode().startswith('forward listener ')
    local_hub = Hub(child.stdout, child.stdin, target)
    hub = asyncio.create_task(local_hub.run())
    try:
        for i in range(2):
            reader, writer = await asyncio.open_connection('127.0.0.1', port)
            message = f'local reverse channel {i}'.encode()
            writer.write(message); await writer.drain()
            assert await reader.readexactly(len(message)) == message
            writer.close(); await writer.wait_closed()
        async with asyncio.timeout(5):
            while local_hub.channels: await asyncio.sleep(.01)
        print('loopback reverse forwarding passed: 2 TCP channels; no SSH or external connection')
    finally:
        child.stdin.close(); await child.wait(); await hub
        server.close(); await server.wait_closed()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stdio-listen', type=int)
    parser.add_argument('--local-check', action='store_true')
    parser.add_argument('--listen-port', type=int)
    parser.add_argument('--target-port', type=int)
    parser.add_argument('--remote-script', default='/home/labuser/nipaplay-next/x45-headless/ssh_stdio_forward.py')
    args = parser.parse_args()
    for port in [args.stdio_listen, args.listen_port, args.target_port]:
        if port is not None and not 1 <= port <= 65535: parser.error('port must be 1–65535')
    if args.local_check: operation = local_check()
    elif args.stdio_listen is not None: operation = listen_stdio(args.stdio_listen)
    elif args.listen_port is not None and args.target_port is not None: operation = forward(args)
    else: parser.error('provide --listen-port and --target-port')
    try: asyncio.run(operation)
    except KeyboardInterrupt: pass
if __name__ == '__main__': main()
