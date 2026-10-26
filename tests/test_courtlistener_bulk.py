import pytest
import structlog.testing

from mogov.loaders import courtlistener_bulk as cl

NS = "http://s3.amazonaws.com/doc/2006-03-01/"


def page(keys, *, token=None, extra=""):
    contents = "".join(f"<Contents><Key>{k}</Key><Size>1</Size></Contents>" for k in keys)
    trunc = (
        f"<IsTruncated>true</IsTruncated><NextContinuationToken>{token}</NextContinuationToken>"
        if token
        else ("<IsTruncated>false</IsTruncated>")
    )
    head = f'<?xml version="1.0"?><ListBucketResult xmlns="{NS}"><Name>b</Name>'
    return f"{head}{extra}{trunc}{contents}</ListBucketResult>".encode()


def key(date):
    return f"bulk-data/people-db-people-{date}.csv.bz2"


def stub(monkeypatch, pages):
    calls = []

    def fake(url, params=None, **kw):
        calls.append(dict(params))
        assert len(calls) < 500, "listing loop did not stop"  # a mutated loop fails fast, not hangs
        return pages[params.get("continuation-token")]

    monkeypatch.setattr(cl, "fetch", fake)
    return calls


def test_namespaced_listing_picks_max(monkeypatch):
    stub(monkeypatch, {None: page([key("2024-01-02"), key("2025-03-04"), key("2023-12-31")])})
    assert cl._latest_snapshot() == "2025-03-04"


def test_follows_pagination_newest_on_page_two(monkeypatch):
    calls = stub(monkeypatch, {None: page([key("2024-01-02")], token="T1"), "T1": page([key("2026-01-01")])})
    assert cl._latest_snapshot() == "2026-01-01"
    assert [c.get("continuation-token") for c in calls] == [None, "T1"]


def test_keys_in_comments_and_cdata_do_not_count(monkeypatch):
    commented = f"<!-- <Key>{key('2030-01-01')}</Key> -->"
    cdata = f"<Note><![CDATA[<Contents><Key>{key('2031-01-01')}</Key></Contents>]]></Note>"
    extra = commented + cdata
    stub(monkeypatch, {None: page([key("2024-01-02")], extra=extra)})
    assert cl._latest_snapshot() == "2024-01-02"


def test_empty_listing_raises(monkeypatch):
    stub(monkeypatch, {None: page([])})
    with pytest.raises(RuntimeError, match="no CourtListener people snapshot"):
        cl._latest_snapshot()


def test_repeated_token_raises_not_hangs(monkeypatch):
    # Every page hands back the same token: a loop that trusts it would never end.
    stub(monkeypatch, {None: page([key("2024-01-02")], token="T"), "T": page([key("2024-01-02")], token="T")})
    with pytest.raises(RuntimeError, match="did not terminate"):
        cl._latest_snapshot()


def test_ignoring_token_fails_fast(monkeypatch):
    # Same fixture, but the fetch stub itself caps calls so a mutated loop fails instead of hanging.
    n = {"c": 0}

    def fake(url, params=None, **kw):
        n["c"] += 1
        assert n["c"] < 500, "listing loop did not stop"
        return page([key("2024-01-02")], token="T")

    monkeypatch.setattr(cl, "fetch", fake)
    with pytest.raises(RuntimeError, match="did not terminate"):
        cl._latest_snapshot()
    assert n["c"] <= cl.MAX_LISTING_PAGES + 2


def test_stray_key_outside_contents_not_counted(monkeypatch):
    stub(monkeypatch, {None: page([key("2024-01-02")], extra=f"<Key>{key('2030-01-01')}</Key>")})
    assert cl._latest_snapshot() == "2024-01-02"


def test_truncated_without_token_warns():
    raw = (
        f'<ListBucketResult xmlns="{NS}"><IsTruncated>true</IsTruncated>'
        f"<Contents><Key>{key('2024-01-02')}</Key></Contents></ListBucketResult>"
    ).encode()
    with structlog.testing.capture_logs() as logs:
        keys, token = cl._parse_listing(raw)
    assert keys == [key("2024-01-02")] and token is None
    assert [e["event"] for e in logs] == ["s3_listing_truncated_without_token"]
    assert logs[0]["log_level"] == "warning"


def test_endless_fresh_tokens_hit_page_cap(monkeypatch):
    n = {"c": 0}

    def fake(url, params=None, **kw):
        n["c"] += 1
        assert n["c"] < 500, "listing loop did not stop"
        return page([key("2024-01-02")], token=f"T{n['c']}")

    monkeypatch.setattr(cl, "fetch", fake)
    with pytest.raises(RuntimeError, match="did not terminate"):
        cl._latest_snapshot()
