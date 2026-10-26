"""mo_state_expenditures loader on fixed Socrata responses (no network)."""

import json
from datetime import date

import duckdb
import pytest

from mogov import db
from mogov.loaders import mo_state_expenditures as mod

THIS_YEAR = date.today().year
ROWS = {
    THIS_YEAR: [
        {
            "fiscal_year": str(THIS_YEAR),
            "agency_name": "LEGISLATURE",
            "category_description": "TRAVEL",
            "detail_description": "LEGISLATIVE DAILY EXPENSE ALLOWANCE",
            "vendor_name": "ADAMS, JOSEPH L",
            "payments_total": "9000.5",
        },
        {
            "fiscal_year": str(THIS_YEAR),
            "agency_name": "LEGISLATURE",
            "category_description": "TRAVEL",
            "detail_description": "IN-STATE MILEAGE",
            "vendor_name": "ADAMS, JOSEPH L",
            "payments_total": "3225.6",
        },
        # a sparse row the portal serves for one payee (seen in FY2025): landed as published
        {"fiscal_year": "KEVIN KRAUS", "agency_name": "11408"},
    ],
    THIS_YEAR - 1: [
        {
            "fiscal_year": str(THIS_YEAR - 1),
            "agency_name": "CORRECTIONS",
            "category_description": "TRAVEL",
            "detail_description": "IN-STATE MILEAGE",
            "vendor_name": "GILMORE, JOSEPH T",
            "payments_total": "-146.4",
        },
    ],
}
DATASETS = {THIS_YEAR: "aaaa-1111", THIS_YEAR - 1: "bbbb-2222"}


@pytest.fixture
def served(tmp_path, monkeypatch):
    """Fake Socrata: a catalog, per-dataset counts, and offset paging of ROWS in order. Returns the request log."""
    monkeypatch.setattr(db, "RAW_DIR", tmp_path)
    monkeypatch.setattr(mod, "PAGE_SIZE", 2)
    by_id = {ds: ROWS[y] for y, ds in DATASETS.items()}
    requests = []

    def fake_fetch(url, params=None, **kw):
        requests.append((url, dict(params or {})))
        if url == mod.CATALOG:
            results = [{"resource": {"id": ds, "name": f"{y} State Expenditures"}} for y, ds in DATASETS.items()]
            results.append({"resource": {"id": "zzzz-9999", "name": "ARRA Grant Expenditures as of COB May 31, 2012"}})
            return json.dumps({"results": results}).encode()
        rows = by_id[url.rsplit("/", 1)[1].removesuffix(".json")]
        if params.get("$select") == "count(*)":
            return json.dumps([{"count": str(len(rows))}]).encode()
        assert params["$order"] == ":id"
        return json.dumps(rows[params["$offset"] : params["$offset"] + params["$limit"]]).encode()

    monkeypatch.setattr(mod, "fetch", fake_fetch)
    return requests


def _landed():
    sql = (
        f"select record_key, payload, source_url from read_parquet('{db.raw_glob('mo_state_expenditures')}') order by 1"
    )
    return duckdb.sql(sql).fetchall()


def test_datasets_come_from_the_catalog_and_skip_other_dataset_families(served):
    assert mod._datasets() == DATASETS


def test_rows_land_verbatim_with_stable_keys_across_pages(served):
    assert mod.load(db.UNSHARDED) == {"mo_state_expenditures": 4}
    landed = _landed()
    assert [k for k, _, _ in landed] == [f"{THIS_YEAR - 1}:1", f"{THIS_YEAR}:1", f"{THIS_YEAR}:2", f"{THIS_YEAR}:3"]
    assert json.loads(landed[1][1]) == ROWS[THIS_YEAR][0]
    assert json.loads(landed[3][1]) == {"fiscal_year": "KEVIN KRAUS", "agency_name": "11408"}  # nothing dropped
    assert landed[1][2].endswith("/aaaa-1111.json")
    assert json.loads(landed[0][1])["payments_total"] == "-146.4"  # refunds keep their sign


def test_rerun_replaces_instead_of_appending(served):
    mod.load(db.UNSHARDED)
    first = _landed()
    mod.load(db.UNSHARDED)
    assert _landed() == first


def test_shards_split_the_years_and_together_land_everything(served):
    counts = [mod.load(db.Shard(i, 2))["mo_state_expenditures"] for i in range(2)]
    assert sorted(counts) in ([1, 3], [0, 4], [4, 0])  # whole years only
    assert sum(counts) == 4
    assert len(_landed()) == 4


def test_a_short_page_fails_rather_than_landing_a_partial_year(served, monkeypatch):
    real = mod.fetch

    def truncating(url, params=None, **kw):
        body = real(url, params, **kw)
        return json.dumps(json.loads(body)[:-1]).encode() if params.get("$offset") == 2 else body

    monkeypatch.setattr(mod, "fetch", truncating)
    with pytest.raises(RuntimeError, match="short"):
        mod.load(db.UNSHARDED)
    assert not db.raw_exists("mo_state_expenditures")
