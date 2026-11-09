#!/usr/bin/env python3
"""Render one canvas artboard through Chrome DevTools Protocol.

Uses only the Python standard library so the reference renderer adds no project
dependency.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import signal
import socket
import struct
import tempfile
import time
from typing import Any
from urllib.parse import urlsplit
from urllib.request import Request, urlopen


SUPPORT_SCRIPT = re.compile(
    r"\s*<script\b[^>]*\bsrc=[\"']\./support\.js[\"'][^>]*>\s*</script>\s*",
    re.IGNORECASE,
)


class CdpSocket:
    def __init__(self, websocket_url: str) -> None:
        endpoint = urlsplit(websocket_url)
        if (
            endpoint.scheme != "ws"
            or endpoint.hostname not in {"127.0.0.1", "localhost"}
            or endpoint.port is None
        ):
            raise RuntimeError(f"Unsupported DevTools URL: {websocket_url}")
        host = endpoint.hostname
        port = endpoint.port
        path = endpoint.path
        self._socket = socket.create_connection((host, port), timeout=20)
        key = base64.b64encode(secrets.token_bytes(16)).decode("ascii")
        request = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        )
        self._socket.sendall(request.encode("ascii"))
        response = self._receive_until(b"\r\n\r\n")
        if not response.startswith(b"HTTP/1.1 101"):
            raise RuntimeError(f"DevTools WebSocket handshake failed: {response!r}")
        expected = base64.b64encode(
            hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()
        )
        if expected.lower() not in response.lower():
            raise RuntimeError("DevTools WebSocket handshake returned a bad accept key")
        self._next_id = 1

    def _receive_until(self, marker: bytes) -> bytes:
        data = bytearray()
        while marker not in data:
            chunk = self._socket.recv(4096)
            if not chunk:
                raise RuntimeError("DevTools WebSocket closed during handshake")
            data.extend(chunk)
        return bytes(data)

    def _read_exact(self, length: int) -> bytes:
        data = bytearray()
        while len(data) < length:
            chunk = self._socket.recv(length - len(data))
            if not chunk:
                raise RuntimeError("DevTools WebSocket closed unexpectedly")
            data.extend(chunk)
        return bytes(data)

    def _send_frame(self, payload: bytes, opcode: int = 1) -> None:
        mask = secrets.token_bytes(4)
        size = len(payload)
        header = bytearray([0x80 | opcode])
        if size < 126:
            header.append(0x80 | size)
        elif size < 65536:
            header.append(0x80 | 126)
            header.extend(struct.pack("!H", size))
        else:
            header.append(0x80 | 127)
            header.extend(struct.pack("!Q", size))
        header.extend(mask)
        masked = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
        self._socket.sendall(header + masked)

    def _receive_message(self) -> dict[str, Any]:
        fragments = bytearray()
        while True:
            first, second = self._read_exact(2)
            final = bool(first & 0x80)
            opcode = first & 0x0F
            masked = bool(second & 0x80)
            size = second & 0x7F
            if size == 126:
                size = struct.unpack("!H", self._read_exact(2))[0]
            elif size == 127:
                size = struct.unpack("!Q", self._read_exact(8))[0]
            mask = self._read_exact(4) if masked else b""
            payload = self._read_exact(size)
            if masked:
                payload = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
            if opcode == 8:
                raise RuntimeError("DevTools WebSocket closed")
            if opcode == 9:
                self._send_frame(payload, opcode=10)
                continue
            if opcode in (0, 1):
                fragments.extend(payload)
            if final and opcode in (0, 1):
                return json.loads(fragments.decode("utf-8"))

    def command(self, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        command_id = self._next_id
        self._next_id += 1
        message: dict[str, Any] = {"id": command_id, "method": method}
        if params is not None:
            message["params"] = params
        self._send_frame(json.dumps(message).encode("utf-8"))
        while True:
            response = self._receive_message()
            if response.get("id") == command_id:
                if "error" in response:
                    raise RuntimeError(f"{method} failed: {response['error']}")
                return response.get("result", {})

    def wait_for(self, method: str) -> dict[str, Any]:
        while True:
            message = self._receive_message()
            if message.get("method") == method:
                return message.get("params", {})

    def close(self) -> None:
        try:
            self._send_frame(b"", opcode=8)
        finally:
            self._socket.close()


def wait_for_devtools(profile: Path, timeout: float = 20) -> int:
    active_port = profile / "DevToolsActivePort"
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if active_port.exists():
            lines = active_port.read_text(encoding="utf-8").splitlines()
            if lines:
                return int(lines[0])
        time.sleep(0.05)
    raise RuntimeError("Chrome did not expose a DevTools port")


def create_target(port: int) -> str:
    request = Request(f"http://127.0.0.1:{port}/json/new?about:blank", method="PUT")
    with urlopen(request, timeout=10) as response:
        target = json.load(response)
    return target["webSocketDebuggerUrl"]


def launch_chrome(executable: str, profile: Path) -> int:
    command = [
        executable,
        "--headless=new",
        "--disable-background-networking",
        "--disable-default-apps",
        "--disable-extensions",
        "--disable-features=Translate",
        "--disable-gpu",
        "--hide-scrollbars",
        "--no-first-run",
        "--remote-debugging-port=0",
        f"--user-data-dir={profile}",
        "about:blank",
    ]
    devnull = os.open(os.devnull, os.O_WRONLY)
    try:
        return os.posix_spawn(
            executable,
            command,
            os.environ,
            file_actions=[
                (os.POSIX_SPAWN_DUP2, devnull, 1),
                (os.POSIX_SPAWN_DUP2, devnull, 2),
            ],
        )
    finally:
        os.close(devnull)


def stop_process(process_id: int) -> None:
    try:
        os.kill(process_id, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        try:
            waited, _ = os.waitpid(process_id, os.WNOHANG)
        except ChildProcessError:
            return
        if waited == process_id:
            return
        time.sleep(0.05)
    try:
        os.kill(process_id, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        os.waitpid(process_id, 0)
    except ChildProcessError:
        pass


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--chrome", required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    args = parser.parse_args()

    source = args.input.read_text(encoding="utf-8")
    stripped, count = SUPPORT_SCRIPT.subn("\n", source)
    if count != 1:
        raise RuntimeError(f"Expected one ./support.js tag in {args.input}, found {count}")

    with tempfile.TemporaryDirectory(prefix="settlo-canvas-") as temporary:
        temp = Path(temporary)
        html = temp / args.input.name
        html.write_text(stripped, encoding="utf-8")
        profile = temp / "chrome-profile"
        profile.mkdir()
        process_id = launch_chrome(args.chrome, profile)
        cdp: CdpSocket | None = None
        try:
            port = wait_for_devtools(profile)
            cdp = CdpSocket(create_target(port))
            cdp.command("Page.enable")
            cdp.command("Runtime.enable")
            cdp.command(
                "Emulation.setDeviceMetricsOverride",
                {
                    "width": args.width,
                    "height": args.height,
                    "deviceScaleFactor": 1,
                    "mobile": False,
                    "screenWidth": args.width,
                    "screenHeight": args.height,
                },
            )
            cdp.command("Page.navigate", {"url": html.resolve().as_uri()})
            cdp.wait_for("Page.loadEventFired")
            font_result = cdp.command(
                "Runtime.evaluate",
                {
                    "expression": """
                      (async () => {
                        await Promise.all([
                          document.fonts.load('400 16px Figtree', 'Settlo'),
                          document.fonts.load('500 16px "IBM Plex Serif"', '0123456789')
                        ]);
                        await document.fonts.ready;
                        return {
                          status: document.fonts.status,
                          figtree: document.fonts.check('400 16px Figtree'),
                          plex: document.fonts.check('500 16px "IBM Plex Serif"')
                        };
                      })()
                    """,
                    "awaitPromise": True,
                    "returnByValue": True,
                },
            )["result"]["value"]
            if font_result != {"status": "loaded", "figtree": True, "plex": True}:
                raise RuntimeError(f"Web fonts did not load: {font_result}")
            screenshot = cdp.command(
                "Page.captureScreenshot",
                {"format": "png", "fromSurface": True, "captureBeyondViewport": False},
            )
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_bytes(base64.b64decode(screenshot["data"]))
        finally:
            if cdp is not None:
                cdp.close()
            stop_process(process_id)


if __name__ == "__main__":
    main()
