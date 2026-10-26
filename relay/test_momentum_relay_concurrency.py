"""Synthetic temporary stores and loopback only; no installed relay state."""
import concurrent.futures
import http.client
import json
import multiprocessing
import os
import sys
import threading
from contextlib import contextmanager
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
import momentum_relay as relay
from test_momentum_relay import snapshot

BASE = snapshot('2026-10-06T10:00:00Z')
OLD = snapshot('2026-10-06T10:01:00Z')
NEW = snapshot('2026-10-06T10:02:00Z')


def _process_upload(path, data, entered, release, started, done):
    original = relay.read_snapshot
    def held_read(target, **kwargs):
        result = original(target, **kwargs)
        entered.set()
        assert release.wait(10), 'release timed out'
        return result
    if entered is not None:
        relay.read_snapshot = held_read
    started.set()
    relay.store_if_newer(Path(path), data)
    done.set()


def test_overlapping_threads_keep_newest(tmp_path, monkeypatch):
    target = tmp_path / 'data.json'
    target.write_bytes(BASE)
    entered, release, started, done = (threading.Event() for _ in range(4))
    original = relay.read_snapshot
    def held_read(path, **kwargs):
        result = original(path, **kwargs)
        if threading.current_thread().name == 'older':
            entered.set()
            assert release.wait(10)
        return result
    monkeypatch.setattr(relay, 'read_snapshot', held_read)
    errors = []
    def upload(data):
        try:
            if data == NEW: started.set()
            relay.store_if_newer(target, data)
            if data == NEW: done.set()
        except BaseException as error: errors.append(error)
    older = threading.Thread(target=upload, args=(OLD,), name='older')
    newer = threading.Thread(target=upload, args=(NEW,))
    older.start()
    try:
        assert entered.wait(5)
        newer.start()
        assert started.wait(5)
        done.wait(.4)  # Lets the unfixed writer replace while the older read is held.
    finally:
        release.set()
        older.join(5)
        if newer.ident is not None: newer.join(5)
    assert not older.is_alive() and not newer.is_alive() and not errors
    assert target.read_bytes() == NEW


def test_overlapping_processes_keep_newest(tmp_path):
    target = tmp_path / 'data.json'
    target.write_bytes(BASE)
    ctx = multiprocessing.get_context('spawn')
    entered, release, start_old, start_new, done_old, done_new = (ctx.Event() for _ in range(6))
    older = ctx.Process(target=_process_upload, args=(str(target), OLD, entered, release, start_old, done_old))
    newer = ctx.Process(target=_process_upload, args=(str(target), NEW, None, release, start_new, done_new))
    older.start()
    try:
        assert entered.wait(5)
        newer.start()
        assert start_new.wait(5)
        done_new.wait(.4)
    finally:
        release.set()
        for process in (older, newer):
            if process.pid:
                process.join(5)
                if process.is_alive(): process.terminate(); process.join(5)
    assert older.exitcode == newer.exitcode == 0
    assert done_old.is_set() and done_new.is_set()
    assert target.read_bytes() == NEW


def test_other_files_progress_while_one_write_is_held(tmp_path, monkeypatch):
    first = tmp_path / 'one' / 'data.json'
    second = tmp_path / 'two' / 'data.json'
    entered, release = threading.Event(), threading.Event()
    original = relay.read_snapshot
    def held_read(path, **kwargs):
        result = original(path, **kwargs)
        if path == first:
            entered.set()
            assert release.wait(10)
        return result
    monkeypatch.setattr(relay, 'read_snapshot', held_read)
    with concurrent.futures.ThreadPoolExecutor(2) as pool:
        pending = pool.submit(relay.store_if_newer, first, OLD)
        try:
            assert entered.wait(5)
            assert pool.submit(relay.store_if_newer, second, NEW).result(3)[0]
            assert second.read_bytes() == NEW
        finally: release.set()
        assert pending.result(5)[0]


@pytest.mark.parametrize('boundary', ['fsync', 'chmod', 'replace'])
def test_failure_preserves_old_bytes_and_releases_for_retry(tmp_path, monkeypatch, boundary):
    target = tmp_path / 'data.json'
    target.write_bytes(BASE)
    def fail(*args, **kwargs): raise OSError('synthetic persistence failure')
    with monkeypatch.context() as patch:
        patch.setattr(Path if boundary == 'chmod' else os, boundary, fail)
        with pytest.raises(OSError, match='synthetic'):
            relay.store_if_newer(target, NEW)
    assert target.read_bytes() == BASE
    assert not list(tmp_path.glob('.MomentumData-*'))
    assert relay.store_if_newer(target, NEW)[0]
    assert target.read_bytes() == NEW


def test_readers_see_complete_previous_then_new_snapshot(tmp_path, monkeypatch):
    target = tmp_path / 'data.json'
    target.write_bytes(BASE)
    entered, release = threading.Event(), threading.Event()
    replace = os.replace
    def held_replace(source, dest):
        entered.set()
        assert release.wait(10)
        replace(source, dest)
    monkeypatch.setattr(os, 'replace', held_replace)
    with concurrent.futures.ThreadPoolExecutor(1) as pool:
        pending = pool.submit(relay.store_if_newer, target, NEW)
        try:
            assert entered.wait(5)
            for _ in range(20): assert relay.read_snapshot(target)[0] == BASE
        finally: release.set()
        assert pending.result(5)[0]
    assert relay.read_snapshot(target)[0] == NEW


@contextmanager
def running_server(path):
    server = relay.make_server('127.0.0.1', 0, path)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try: yield server.server_address
    finally:
        server.shutdown(); server.server_close(); thread.join(5)


def request(address, method, route, body=None):
    connection = http.client.HTTPConnection(*address, timeout=5)
    try:
        connection.request(method, route, body=body)
        response = connection.getresponse()
        return response.status, response.read()
    finally: connection.close()


def test_http_success_stale_equal_and_validation_contract(tmp_path):
    target = tmp_path / 'data.json'
    with running_server(target) as address:
        assert request(address, 'GET', '/data')[0] == 404
        assert json.loads(request(address, 'GET', '/health')[1])['hasData'] is False
        for route, data, expected in [('/momentum/data', NEW, True), ('/data', OLD, False), ('/data', NEW, True)]:
            status, raw = request(address, 'PUT', route, data)
            assert status == 200 and json.loads(raw)['stored'] is expected
        equal_changed = NEW.replace(b'"app"', b'"other-app"')
        assert json.loads(request(address, 'PUT', '/data', equal_changed)[1])['stored'] is True
        assert request(address, 'GET', '/momentum/data') == (200, equal_changed)
        assert json.loads(request(address, 'GET', '/momentum/health')[1])['hasData'] is True
        assert request(address, 'PUT', '/data', b'{}')[0] == 400
        assert request(address, 'GET', '/missing')[0] == 404
        assert target.read_bytes() == equal_changed


def test_http_overlapping_uploads_keep_newest(tmp_path, monkeypatch):
    target = tmp_path / 'data.json'
    target.write_bytes(BASE)
    entered, release = threading.Event(), threading.Event()
    original = relay.read_snapshot
    first = True
    guard = threading.Lock()
    def held_read(path, **kwargs):
        nonlocal first
        result = original(path, **kwargs)
        with guard:
            hold = first
            first = False
        if hold:
            entered.set()
            assert release.wait(10)
        return result
    monkeypatch.setattr(relay, 'read_snapshot', held_read)
    with running_server(target) as address, concurrent.futures.ThreadPoolExecutor(2) as pool:
        older = pool.submit(request, address, 'PUT', '/data', OLD)
        try:
            assert entered.wait(5)
            newer = pool.submit(request, address, 'PUT', '/momentum/data', NEW)
            concurrent.futures.wait([newer], timeout=.4)
        finally: release.set()
        assert older.result(5)[0] == newer.result(5)[0] == 200
        assert request(address, 'GET', '/data') == (200, NEW)


def test_http_persistence_failure_is_error_and_retry_works(tmp_path, monkeypatch):
    target = tmp_path / 'data.json'
    target.write_bytes(BASE)
    with running_server(target) as address:
        with monkeypatch.context() as patch:
            def fail(*args): raise OSError('synthetic failure with private path')
            patch.setattr(os, 'replace', fail)
            status, raw = request(address, 'PUT', '/data', NEW)
            assert status == 500
            assert json.loads(raw) == {'error': 'snapshot_persistence_failed'}
        assert request(address, 'GET', '/data') == (200, BASE)
        assert request(address, 'PUT', '/data', NEW)[0] == 200
        assert request(address, 'GET', '/data') == (200, NEW)


def test_failed_read_cannot_authorize_overwriting_saved_snapshot(tmp_path, monkeypatch):
    target = tmp_path / 'data.json'
    target.write_bytes(NEW)
    original = Path.read_bytes
    with monkeypatch.context() as patch:
        def failed_read(path):
            if path == target: raise PermissionError('synthetic unreadable snapshot')
            return original(path)
        patch.setattr(Path, 'read_bytes', failed_read)
        assert relay.read_snapshot(target) is None  # Existing read-only API behavior.
        with pytest.raises(PermissionError): relay.store_if_newer(target, OLD)
    assert target.read_bytes() == NEW
    assert relay.store_if_newer(target, OLD)[0] is False
