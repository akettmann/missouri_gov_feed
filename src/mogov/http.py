"""HTTP client with an on-disk cache so re-runs don't re-hit public servers."""

import hashlib
import json
import time
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
) -> bytes:
    """GET url, returning bytes. Responses younger than max_age seconds come from cache (None = always cache).

    delay: seconds to sleep before a network request (not on cache hits), to stay polite to small state sites.
    cache_only: never touch the network; return any cached copy regardless of age, else raise CacheMiss.
    """
    path = _cache_path(url, params)
    host = httpx.URL(url).host
    if path.exists() and (cache_only or max_age is None or time.time() - path.stat().st_mtime < max_age):
        obs.http_requests.add(1, {"host": host, "cache_hit": True})
        return path.read_bytes()
    if cache_only:
        raise CacheMiss(url)
    if delay:
        time.sleep(delay)
    obs.http_requests.add(1, {"host": host, "cache_hit": False})
    for attempt in range(retries):
        resp = client().get(url, params=params, headers=headers)
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
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(resp.content)
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
    if path.exists() and (max_age is None or time.time() - path.stat().st_mtime < max_age):
        return path.read_bytes()
    if delay:
        time.sleep(delay)
    resp = client().post(url, data=data, json=json_body, headers=headers)
    resp.raise_for_status()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(resp.content)
    return resp.content


def fetch_to_file(url: str, dest: Path, *, max_age: float | None = 86400) -> Path:
    """Stream a large download to dest, skipping it if a fresh copy exists."""
    if dest.exists() and (max_age is None or time.time() - dest.stat().st_mtime < max_age):
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    with client().stream("GET", url) as resp:
        resp.raise_for_status()
        with tmp.open("wb") as fh:
            for chunk in resp.iter_bytes(1 << 20):
                fh.write(chunk)
    tmp.replace(dest)
    return dest
