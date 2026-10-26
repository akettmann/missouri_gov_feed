import pytest

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
