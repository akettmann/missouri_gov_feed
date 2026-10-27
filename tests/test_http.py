import threading
import time

import pytest

from mogov import http


def test_concurrent_callers_download_once(tmp_path, monkeypatch):
    calls = []

    def slow_stream(url, dest, lock):
        calls.append(url)
        time.sleep(0.3)
        dest.write_bytes(b"data")

    monkeypatch.setattr(http, "_stream", slow_stream)
    dest = tmp_path / "big.zip"
    url = "https://example.test/big.zip"
    threads = [threading.Thread(target=http.fetch_to_file, args=(url, dest)) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert calls == [url]
    assert dest.read_bytes() == b"data"
    assert not list(tmp_path.glob(".*.lock"))


def test_stale_lock_is_taken_over(tmp_path, monkeypatch):
    monkeypatch.setattr(http, "LOCK_STALE_S", 0)
    lock = tmp_path / ".x.lock"
    lock.touch()  # left by a crashed process
    with http._single_flight(tmp_path / "x") as held:
        assert held == lock
    assert not lock.exists()


def test_lock_create_permission_error_means_held(tmp_path, monkeypatch):
    # Windows: creating a lock file whose delete is still pending raises PermissionError, not FileExistsError
    real_open, failures = http.os.open, [PermissionError(13, "Permission denied")]

    def flaky_open(path, flags, *args):
        if failures:
            raise failures.pop()
        return real_open(path, flags, *args)

    monkeypatch.setattr(http.os, "open", flaky_open)
    monkeypatch.setattr(http.time, "sleep", lambda s: None)
    with http._single_flight(tmp_path / "x") as held:
        assert held.exists()
    assert not failures


def test_replace_file_retries_permission_errors(tmp_path, monkeypatch):
    src, dest = tmp_path / "a", tmp_path / "b"
    src.write_bytes(b"new")
    real_replace, failures = type(src).replace, [PermissionError("[WinError 5] Access is denied")] * 2

    def flaky_replace(self, target):
        if failures:
            raise failures.pop()
        return real_replace(self, target)

    monkeypatch.setattr(type(src), "replace", flaky_replace)
    http.replace_file(src, dest)
    assert dest.read_bytes() == b"new"


def test_write_atomic_same_pid_writers_do_not_share_tmp(tmp_path, monkeypatch):
    """Containers of one job can all be pid 1 on a shared volume: one writer's failure must not delete
    (or its write clobber) the other's in-flight temp file."""
    monkeypatch.setattr(http.os, "getpid", lambda: 1)
    target = tmp_path / "entry.bin"
    seen = []
    real_replace = http.replace_file

    def interleaved(tmp, dest, attempts=10):
        seen.append(tmp)
        if len(seen) == 1:  # writer A paused between write and replace: writer B runs completely, and fails
            monkeypatch.setattr(http, "replace_file", boom)
            with pytest.raises(RuntimeError):
                http.write_atomic(target, b"B")
            monkeypatch.setattr(http, "replace_file", interleaved)
            assert tmp.read_bytes() == b"A"  # B's cleanup left A's temp file alone
        real_replace(tmp, dest, attempts)

    def boom(tmp, dest, attempts=10):
        seen.append(tmp)
        raise RuntimeError

    monkeypatch.setattr(http, "replace_file", interleaved)
    http.write_atomic(target, b"A")
    assert target.read_bytes() == b"A"
    assert seen[0] != seen[1]
    assert [p.name for p in tmp_path.iterdir()] == ["entry.bin"]


def test_sweep_stale_parts_removes_only_old_parts_of_that_file(tmp_path):
    import os

    target = tmp_path / "big.zip"
    old, new, other = (tmp_path / n for n in (".big.zip.1.aa.part", ".big.zip.1.bb.part", ".other.zip.1.aa.part"))
    for p in (old, new, other):
        p.write_bytes(b"x")
    os.utime(old, (0, 0))
    os.utime(other, (0, 0))
    http.sweep_stale_parts(target)
    assert not old.exists()
    assert new.exists()
    assert other.exists()
