"""HTTP client with an on-disk cache so re-runs don't re-hit public servers."""

import contextlib
import hashlib
import json
import os
import time
from collections.abc import Callable, Iterator
from pathlib import Path

import httpx

from mogov import obs
from mogov.config import CACHE_DIR, USER_AGENT

_client: httpx.Client | None = None


def client() -> httpx.Client:
    global _client
    if _client is None:
        _client = httpx.Client(
            headers={"User-Agent": USER_AGENT},
            follow_redirects=True,
            timeout=httpx.Timeout(120.0, connect=30.0),
        )
    return _client


def _cache_path(url: str, params: dict | None) -> Path:
    key = url + "?" + "&".join(f"{k}={v}" for k, v in sorted((params or {}).items()) if k != "api_key")
    return CACHE_DIR / hashlib.sha256(key.encode()).hexdigest()


def _fresh(path: Path, max_age: float | None) -> bool:
    return path.exists() and (max_age is None or time.time() - path.stat().st_mtime < max_age)


def replace_file(tmp: Path, dest: Path, attempts: int = 10) -> None:
    """tmp.replace(dest), retried: Windows refuses to replace a file that another process has open (a shard
    reading the cached copy) or is replacing at the same moment ("[WinError 5] Access is denied")."""
    for attempt in range(attempts):
        try:
            tmp.replace(dest)
            return
        except PermissionError:
            if attempt == attempts - 1:
                raise
            time.sleep(0.1 * (attempt + 1))


def write_atomic(path: Path, content: bytes) -> None:
    """Shards share the cache; never let another process read a half-written entry."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.part")
    try:
        tmp.write_bytes(content)
        replace_file(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


# A lock file untouched for this long belongs to a process that died; downloads refresh it as they stream.
LOCK_STALE_S = 300


@contextlib.contextmanager
def _single_flight(path: Path) -> Iterator[Path]:
    """Shards that need the same URL download it once: the first takes a lock file next to the cache entry,
    the others wait for it to go away and then find the fresh copy in the cache. Yields the lock path."""
    path.parent.mkdir(parents=True, exist_ok=True)
    lock = path.with_name(f".{path.name}.lock")
    while True:
        try:
            os.close(os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
            break
        # Windows raises PermissionError instead of FileExistsError while another shard's unlink of the lock is
        # still pending (a peer has it open for stat); either way the lock is taken, so wait.
        except (FileExistsError, PermissionError):
            with contextlib.suppress(FileNotFoundError, PermissionError):
                if time.time() - lock.stat().st_mtime > LOCK_STALE_S:
                    lock.unlink(missing_ok=True)
            time.sleep(0.5)
    try:
        yield lock
    finally:
        lock.unlink(missing_ok=True)


# A throttle lock is held across one sleep (the interval) plus one request (timeout 120 s), so a lock this old
# belongs to a process that died.
THROTTLE_LOCK_STALE_S = 300


@contextlib.contextmanager
def host_throttle(
    host: str,
    interval: float,
    *,
    clock: Callable[[], float] = time.time,
    sleep: Callable[[float], None] = time.sleep,
) -> Iterator[None]:
    """Hold the host's lock across a request that starts at least `interval` seconds after the last one any
    process on this machine started.

    Processes share two files in CACHE_DIR: a lock and the time the last request started. The holder sleeps out
    the rest of the interval, stamps the new start time and yields, so every process (shards of one run, two runs,
    a shard and a re-run) serialises its requests to the host. The wall clock is used because processes cannot
    compare monotonic clocks. This needs a shared filesystem: Cloud Run tasks don't share one, so a source that
    depends on it must not be split over several tasks.
    """
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    lock = CACHE_DIR / f".throttle-{host}.lock"
    stamp = CACHE_DIR / f".throttle-{host}.last"
    while True:
        try:
            os.close(os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
            break
        except (FileExistsError, PermissionError):  # PermissionError: Windows, a peer's unlink is pending
            with contextlib.suppress(FileNotFoundError, PermissionError):
                if time.time() - lock.stat().st_mtime > THROTTLE_LOCK_STALE_S:
                    lock.unlink(missing_ok=True)
            time.sleep(0.02)
    try:
        try:
            last = float(stamp.read_text())
        except (FileNotFoundError, ValueError):
            last = float("-inf")
        # a stamp in the future (clock set back) must not stall the run for longer than one interval
        wait = min(last + interval - clock(), interval)
        if wait > 0:
            sleep(wait)
        write_atomic(stamp, repr(clock()).encode())
        yield
    finally:
        lock.unlink(missing_ok=True)


def _record(host: str, resp: httpx.Response, started: float) -> None:
    obs.http_duration.record(time.perf_counter() - started, {"host": host, "status": resp.status_code})
    obs.http_bytes.add(len(resp.content), {"host": host})


class RateLimited(httpx.HTTPError):
    """The server's quota is exhausted for longer than is worth waiting (Retry-After > 2 minutes)."""

    def __init__(self, host: str, retry_after: float):
        super().__init__(f"{host} rate limit exhausted; retry after {retry_after:.0f}s")
        self.host, self.retry_after = host, retry_after


class CacheMiss(LookupError):
    """cache_only fetch with nothing cached."""


def _retry_after(resp: httpx.Response) -> float | None:
    try:
        return float(resp.headers["retry-after"])
    except (KeyError, ValueError):
        return None


def fetch(
    url: str,
    params: dict | None = None,
    *,
    max_age: float | None = 86400,
    retries: int = 4,
    headers: dict | None = None,
    delay: float = 0.0,
    cache_only: bool = False,
    check: Callable[[httpx.Response], None] | None = None,
    min_interval: float = 0.0,
) -> bytes:
    """GET url, returning bytes. Responses younger than max_age seconds come from cache (None = always cache).

    delay: seconds to sleep before a network request (not on cache hits), to stay polite to small state sites.
    cache_only: never touch the network; return any cached copy regardless of age, else raise CacheMiss.
    min_interval: requests to this host from every process sharing CACHE_DIR start at least this many seconds apart
    (host_throttle), unlike `delay`, which each process counts on its own clock.
    check: called with each successful response before it is cached; raise to reject it (e.g. a block page
    served with 200 after a redirect), so it is never cached.
    """
    path = _cache_path(url, params)
    host = httpx.URL(url).host
    if _fresh(path, None if cache_only else max_age):
        obs.http_requests.add(1, {"host": host, "cache_hit": True})
        return path.read_bytes()
    if cache_only:
        raise CacheMiss(url)
    with _single_flight(path):
        if _fresh(path, max_age):  # another shard fetched it while we waited
            obs.http_requests.add(1, {"host": host, "cache_hit": True})
            return path.read_bytes()
        return _get(
            url,
            params,
            path,
            host,
            retries=retries,
            headers=headers,
            delay=delay,
            check=check,
            min_interval=min_interval,
        )


def _get(
    url: str,
    params: dict | None,
    path: Path,
    host: str,
    *,
    retries: int,
    headers: dict | None,
    delay: float,
    check: Callable[[httpx.Response], None] | None = None,
    min_interval: float = 0.0,
):
    if delay:
        time.sleep(delay)
    obs.http_requests.add(1, {"host": host, "cache_hit": False})
    for attempt in range(retries):
        with host_throttle(host, min_interval) if min_interval else contextlib.nullcontext():
            started = time.perf_counter()
            resp = client().get(url, params=params, headers=headers)
        _record(host, resp, started)
        if resp.status_code == 429:
            wait = _retry_after(resp)
            if wait is not None and wait > 120:  # a quota (e.g. N/day), not a burst limit: don't sit and retry
                raise RateLimited(host, wait)
            time.sleep(wait if wait is not None else min(60, 2**attempt * 5))
            continue
        if resp.status_code >= 500:
            time.sleep(min(60, 2**attempt * 5))
            continue
        resp.raise_for_status()
        if check:
            check(resp)
        write_atomic(path, resp.content)
        return resp.content
    resp.raise_for_status()
    raise httpx.HTTPError(f"gave up on {url} after {retries} attempts (last status {resp.status_code})")


def post(
    url: str,
    *,
    data: dict | None = None,
    json_body: object = None,
    headers: dict | None = None,
    max_age: float | None = 86400,
    delay: float = 0.0,
) -> bytes:
    """Cached POST (GraphQL / SPARQL / search forms). The cache key includes the request body."""
    body_key = json.dumps({"data": data, "json": json_body}, sort_keys=True, default=str)
    path = _cache_path(url, {"__post__": hashlib.sha256(body_key.encode()).hexdigest()})
    host = httpx.URL(url).host
    if not _fresh(path, max_age):
        with _single_flight(path):
            if not _fresh(path, max_age):
                if delay:
                    time.sleep(delay)
                obs.http_requests.add(1, {"host": host, "cache_hit": False})
                started = time.perf_counter()
                resp = client().post(url, data=data, json=json_body, headers=headers)
                _record(host, resp, started)
                resp.raise_for_status()
                write_atomic(path, resp.content)
                return resp.content
    obs.http_requests.add(1, {"host": host, "cache_hit": True})
    return path.read_bytes()


def fetch_to_file(url: str, dest: Path, *, max_age: float | None = 86400) -> Path:
    """Stream a large download to dest, skipping it if a fresh copy exists. Concurrent callers (shards)
    download it once; the rest wait for that copy."""
    if _fresh(dest, max_age):
        return dest
    with _single_flight(dest) as lock:
        if not _fresh(dest, max_age):
            _stream(url, dest, lock)
    return dest


def _stream(url: str, dest: Path, lock: Path) -> None:
    tmp = dest.with_name(f".{dest.name}.{os.getpid()}.part")
    touched = time.time()
    obs.http_requests.add(1, {"host": httpx.URL(url).host, "cache_hit": False})
    try:
        with client().stream("GET", url) as resp:
            resp.raise_for_status()
            size = int(resp.headers.get("content-length") or 0)
            progress = obs.Progress(f"download {dest.name} (MiB)", size >> 20) if size > 64 << 20 else None
            with tmp.open("wb") as fh:
                for chunk in resp.iter_bytes(1 << 20):
                    fh.write(chunk)
                    obs.http_bytes.add(len(chunk), {"host": resp.url.host})
                    if progress:
                        progress.tick(len(chunk) / (1 << 20))
                    if time.time() - touched > 30:  # heartbeat: waiting shards must not think we died
                        lock.touch()
                        touched = time.time()
            if progress:
                progress.finish()
        replace_file(tmp, dest)
    finally:
        tmp.unlink(missing_ok=True)
