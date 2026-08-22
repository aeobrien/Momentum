import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
from momentum_relay import read_snapshot, store_if_newer, validate_snapshot


def snapshot(modified: str) -> bytes:
    return json.dumps(
        {
            "tasks": [],
            "routines": [],
            "completionHistory": [],
            "lastModified": modified,
            "lastModifiedBy": "app",
        }
    ).encode()


def test_rejects_json_without_the_shared_data_contract() -> None:
    with pytest.raises(ValueError, match="tasks must be an array"):
        validate_snapshot(b'{"lastModified":"2026-08-22T10:00:00Z"}')


def test_stores_a_valid_snapshot_atomically(tmp_path: Path) -> None:
    target = tmp_path / "private" / "MomentumData.json"
    stored, _ = store_if_newer(target, snapshot("2026-08-22T10:00:00Z"))

    assert stored is True
    assert read_snapshot(target) is not None
    assert target.stat().st_mode & 0o777 == 0o600


def test_an_older_retry_cannot_replace_newer_data(tmp_path: Path) -> None:
    target = tmp_path / "MomentumData.json"
    newest = snapshot("2026-08-22T10:01:00Z")
    older = snapshot("2026-08-22T10:00:00Z")

    assert store_if_newer(target, newest)[0] is True
    assert store_if_newer(target, older)[0] is False
    assert target.read_bytes() == newest
