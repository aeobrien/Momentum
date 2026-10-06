#!/usr/bin/env python3
"""Small private relay for Momentum's latest exported snapshot.

The process binds to localhost. Tailscale Serve supplies the private HTTPS front
door, so the payload is available only to devices signed into Aidan's tailnet.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import tempfile
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


MAX_PAYLOAD_BYTES = 16 * 1024 * 1024
DATA_PATHS = {"/data", "/momentum/data"}
HEALTH_PATHS = {"/health", "/momentum/health"}


def _parse_timestamp(value: object) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def validate_snapshot(data: bytes) -> tuple[dict, datetime]:
    try:
        payload = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"body is not valid JSON: {exc}") from exc
    if not isinstance(payload, dict):
        raise ValueError("body must be a JSON object")
    for key in ("tasks", "routines", "completionHistory"):
        if not isinstance(payload.get(key), list):
            raise ValueError(f"{key} must be an array")
    modified = _parse_timestamp(payload.get("lastModified"))
    if modified is None:
        raise ValueError("lastModified must be an ISO-8601 timestamp")
    return payload, modified


def read_snapshot(path: Path, *, raise_on_io_error: bool = False) -> tuple[bytes, datetime] | None:
    try:
        data = path.read_bytes()
        _, modified = validate_snapshot(data)
        return data, modified
    except (FileNotFoundError, ValueError):
        return None
    except OSError:
        if raise_on_io_error:
            raise
        return None


def store_if_newer(path: Path, data: bytes) -> tuple[bool, datetime]:
    _, incoming_modified = validate_snapshot(data)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    # A stable sibling inode is essential: the snapshot inode changes on replace.
    # Open separately for every call so flock also serializes threads in this
    # process. Never unlink the lock file: waiters must share the same inode.
    lock_path = path.with_name(f".{path.name}.lock")
    lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(lock_fd, "rb") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        current = read_snapshot(path, raise_on_io_error=True)
        if current is not None and current[1] > incoming_modified:
            return False, current[1]

        fd, temporary_name = tempfile.mkstemp(prefix=".MomentumData-", dir=path.parent)
        temporary = Path(temporary_name)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            temporary.chmod(0o600)
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)
        # Closing the descriptor releases ownership on success or any exception.
        return True, incoming_modified


class MomentumRelayHandler(BaseHTTPRequestHandler):
    server_version = "MomentumRelay/1"

    @property
    def data_path(self) -> Path:
        return self.server.data_path  # type: ignore[attr-defined]

    def _json(self, status: HTTPStatus, body: dict) -> None:
        encoded = json.dumps(body, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        request_path = urlsplit(self.path).path
        if request_path in HEALTH_PATHS:
            current = read_snapshot(self.data_path)
            self._json(
                HTTPStatus.OK,
                {
                    "status": "ok",
                    "hasData": current is not None,
                    "lastModified": current[1].isoformat() if current else None,
                },
            )
            return
        if request_path not in DATA_PATHS:
            self._json(HTTPStatus.NOT_FOUND, {"error": "not_found"})
            return
        current = read_snapshot(self.data_path)
        if current is None:
            self._json(HTTPStatus.NOT_FOUND, {"error": "no_momentum_data"})
            return
        data, _ = current
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_PUT(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if urlsplit(self.path).path not in DATA_PATHS:
            self._json(HTTPStatus.NOT_FOUND, {"error": "not_found"})
            return
        try:
            length = int(self.headers.get("Content-Length", ""))
        except ValueError:
            length = -1
        if length < 1:
            self._json(HTTPStatus.LENGTH_REQUIRED, {"error": "content_length_required"})
            return
        if length > MAX_PAYLOAD_BYTES:
            self._json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "payload_too_large"})
            return
        data = self.rfile.read(length)
        try:
            stored, modified = store_if_newer(self.data_path, data)
        except ValueError as exc:
            self._json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return
        except OSError:
            self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": "snapshot_persistence_failed"})
            return
        self._json(
            HTTPStatus.OK,
            {"status": "ok", "stored": stored, "lastModified": modified.isoformat()},
        )

    def log_message(self, format: str, *args: object) -> None:
        print(f"{self.address_string()} - {format % args}", flush=True)


def make_server(host: str, port: int, data_path: Path) -> ThreadingHTTPServer:
    server = ThreadingHTTPServer((host, port), MomentumRelayHandler)
    server.data_path = data_path  # type: ignore[attr-defined]
    return server


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8796)
    parser.add_argument(
        "--data",
        type=Path,
        default=Path.home() / "Library/Application Support/MomentumRelay/MomentumData.json",
    )
    args = parser.parse_args()
    server = make_server(args.host, args.port, args.data)
    print(f"Momentum relay listening on {args.host}:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
