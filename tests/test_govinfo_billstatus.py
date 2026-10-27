import gzip
import io
import zipfile
from datetime import date, datetime
from pathlib import Path

import duckdb
import httpx
import pytest

from mogov import db
from mogov.loaders import govinfo_billstatus as loader
from mogov.parsers import govinfo_billstatus as parser

FIXTURES = Path(__file__).parent / "fixtures" / "govinfo_billstatus"
# Both trimmed from the real 118th-Congress files: a vetoed Senate joint resolution (S.J.Res. 32, which failed
# the override vote 54-45) and an enacted House joint resolution (H.J.Res. 26, Public Law 118-1).
SJRES = (FIXTURES / "BILLSTATUS-118sjres32.xml").read_bytes()
HJRES = (FIXTURES / "BILLSTATUS-118hjres26.xml").read_bytes()


def test_bill_row_is_read_from_direct_children_only():
    bill = parser.parse_bill(HJRES, "f.xml")["bills"]
    assert bill[0][0] == "118-hjres-26"
    row = bill[0][1]
    # the committee <type>Standing</type> and the action <type> elements must not leak into the bill's own type
    assert row["bill_type"] == "HJRES"
    assert (row["congress"], row["number"], row["origin_chamber"]) == ("118", "26", "House")
    assert row["introduced_date"] == "2023-02-02"
    assert row["latest_action_text"].startswith("Became Public Law")


def test_sponsor_and_cosponsor_rows_carry_bioguide_ids_and_flags():
    rows = parser.parse_bill(SJRES, "f.xml")
    ((_, sponsor),) = rows["sponsors"]
    assert (sponsor["bioguide_id"], sponsor["state"], sponsor["district"]) == ("K000393", "LA", None)
    assert sponsor["is_by_request"] == "N"
    keys = [k for k, _ in rows["cosponsors"]]
    assert keys == ["118-sjres-32#0", "118-sjres-32#1", "118-sjres-32#2"]
    first = rows["cosponsors"][0][1]
    assert (first["bioguide_id"], first["sponsorship_date"], first["is_original_cosponsor"]) == (
        "L000571",
        "2023-06-13",
        "True",
    )
    assert first["middle_name"] == "M."
    house = parser.parse_bill(HJRES, "f.xml")["sponsors"][0][1]
    assert (house["state"], house["district"]) == ("GA", "9")


def test_law_number_is_extracted_and_a_bill_without_one_has_none():
    assert [p["law_number"] for _, p in parser.parse_bill(HJRES, "f.xml")["laws"]] == ["118-1"]
    assert parser.parse_bill(SJRES, "f.xml")["laws"] == []


def test_recorded_votes_point_at_the_action_that_cites_them():
    votes = parser.parse_bill(SJRES, "f.xml")["recorded_votes"]
    assert votes
    key, vote = votes[0]
    assert key == "118-sjres-32#0#0"
    assert (vote["chamber"], vote["roll_number"], vote["session_number"], vote["congress"]) == (
        "Senate",
        "5",
        "2",
        "118",
    )
    assert vote["vote_date"] == "2024-01-10T21:14:54Z"
    assert vote["action_position"] == 0


def test_actions_keep_order_and_the_nested_source_system_name():
    actions = parser.parse_bill(HJRES, "f.xml")["actions"]
    assert [p["action_type"] for _, p in actions] == ["President", "BecameLaw", "President"]
    assert [p["position"] for _, p in actions] == [0, 1, 2]
    assert actions[1][1]["action_code"] == "36000"
    assert actions[1][1]["source_system"] == "Library of Congress"


def test_row_keys_are_unique_and_reparse_identically():
    first = parser.parse_bill(SJRES, "f.xml")
    for table_rows in first.values():
        keys = [k for k, _ in table_rows]
        assert len(keys) == len(set(keys))
    assert parser.parse_bill(SJRES, "f.xml") == first


def test_blank_elements_are_none_not_empty_strings():
    xml = (
        b"<billStatus><bill><number>1</number><type>HR</type><congress>1</congress><title> </title></bill></billStatus>"
    )
    row = parser.parse_bill(xml, "f.xml")["bills"][0][1]
    assert row["title"] is None
    assert row["bill_id"] == "1-hr-1"


def test_a_file_without_a_bill_is_rejected():
    with pytest.raises(ValueError, match="no <bill>"):
        parser.parse_bill(b"<html><body>error</body></html>", "x.xml")


def test_entities_are_not_resolved():
    xml = (
        b'<!DOCTYPE b [<!ENTITY x SYSTEM "file:///etc/passwd">]>'
        b"<billStatus><bill><number>1</number><type>HR</type><congress>1</congress><title>&x;</title></bill></billStatus>"
    )
    assert "root:" not in (parser.parse_bill(xml, "f.xml")["bills"][0][1]["title"] or "")


# ---- current Congress ----------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("day", "congress"),
    [
        (date(2025, 1, 3), 119),
        (date(2026, 10, 27), 119),
        (date(2027, 1, 2), 119),  # still the 119th until January 3
        (date(2027, 1, 3), 120),
        (date(2023, 6, 1), 118),
        (date(2017, 1, 2), 114),
    ],
)
def test_congress_comes_from_the_date(day, congress):
    assert loader.congress_on(day) == congress


@pytest.mark.parametrize(
    ("day", "expected"),
    [
        (date(2026, 10, 27), [117, 118, 119]),
        (date(2027, 1, 2), [117, 118, 119]),  # the 120th has not begun
        (date(2027, 1, 3), [117, 118, 119, 120]),
        (date(2029, 6, 1), [117, 118, 119, 120, 121]),
    ],
)
def test_default_congresses_end_at_the_congress_in_session(day, expected):
    assert loader.default_congresses(day) == expected


def test_load_uses_the_date_derived_default_when_nothing_is_configured(site, monkeypatch):
    monkeypatch.setattr(loader, "CONGRESSES", None)
    monkeypatch.setattr(loader, "default_congresses", lambda day: [118])
    loader.load(db.UNSHARDED)
    assert sorted(site) == sorted(loader.zip_url(118, t) for t in ("hjres", "sjres", "sres"))


@pytest.mark.parametrize(
    ("day", "congress", "expected"),
    [
        (date(2026, 10, 27), 119, 86400),
        (date(2026, 10, 27), 118, 30 * 86400),
        (date(2027, 1, 2), 119, 86400),
        (date(2027, 1, 3), 120, 86400),
        (date(2027, 1, 5), 119, 86400),  # outgoing Congress: late signings
        (date(2027, 2, 28), 119, 86400),
        (date(2027, 3, 1), 119, 30 * 86400),  # grace is over
        (date(2027, 1, 5), 118, 30 * 86400),
        (date(2027, 1, 5), 121, 30 * 86400),
        (date(2026, 1, 15), 118, 30 * 86400),  # Jan-Feb of the Congress's second year: no grace
        (date(2027, 1, 2), 118, 30 * 86400),  # before the 120th starts, 118th is two back
        (date(2028, 1, 10), 119, 30 * 86400),  # second year of the 120th: no grace
    ],
)
def test_max_age_keeps_the_outgoing_congress_daily_until_march(day, congress, expected):
    assert loader.max_age(congress, day) == expected


@pytest.mark.parametrize(
    ("today", "configured", "expected"),
    [
        (date(2026, 10, 27), [118, 119], {"sjres119": 86400, "sjres118": 30 * 86400}),
        (date(2026, 10, 27), [117, 118], {"sjres118": 30 * 86400, "sjres117": 30 * 86400}),  # 119th not loaded
        (date(2027, 1, 5), [119, 120], {"sjres120": 86400, "sjres119": 86400}),
        (date(2027, 3, 2), [119, 120], {"sjres120": 86400, "sjres119": 30 * 86400}),
    ],
)
def test_load_picks_each_zips_age_from_the_date(site, monkeypatch, today, configured, expected):
    ages = {}
    fake = loader.fetch_to_file

    def spy(url, dest, *, max_age):
        ages[url.split("/")[-2] + url.split("/")[-3]] = max_age
        return fake(url, dest, max_age=max_age)

    class Clock(datetime):
        @classmethod
        def now(cls, tz=None):
            return datetime(today.year, today.month, today.day, 12, tzinfo=tz)

    monkeypatch.setattr(loader, "datetime", Clock)
    monkeypatch.setattr(loader, "fetch_to_file", spy)
    monkeypatch.setattr(loader, "CONGRESSES", configured)
    monkeypatch.setattr(loader, "BILL_TYPES", ["sjres"])
    loader.load(db.UNSHARDED)
    assert ages == expected


def test_load_reads_the_clock_once(site, monkeypatch):
    reads = []

    class Clock(datetime):
        @classmethod
        def now(cls, tz=None):
            reads.append(1)
            return datetime(2027, 1, 2, 23, 59, tzinfo=tz)

    monkeypatch.setattr(loader, "datetime", Clock)
    monkeypatch.setattr(loader, "CONGRESSES", None)
    monkeypatch.setattr(loader, "BILL_TYPES", ["sjres"])
    loader.load(db.UNSHARDED)
    # land_file stamps landed_at per file (one fetched zip member here); the date itself is read once
    assert len(reads) - len(_rows("govinfo_billstatus_files")) == 1


# ---- loader --------------------------------------------------------------------------------------------------


def _zip(**files: bytes) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        for name, data in files.items():
            zf.writestr(name, data)
    return buf.getvalue()


@pytest.fixture
def site(tmp_path, monkeypatch):
    """A fake govinfo with a 118th-Congress sjres zip and hjres zip; every other zip is a 404."""
    zips = {
        "https://www.govinfo.gov/bulkdata/BILLSTATUS/118/sjres/BILLSTATUS-118-sjres.zip": _zip(
            **{"BILLSTATUS-118sjres32.xml": SJRES}
        ),
        "https://www.govinfo.gov/bulkdata/BILLSTATUS/118/hjres/BILLSTATUS-118-hjres.zip": _zip(
            **{"BILLSTATUS-118hjres26.xml": HJRES, "readme.txt": b"not xml"}
        ),
    }
    requests = []

    def fake_fetch_to_file(url, dest, *, max_age):
        requests.append(url)
        if url not in zips:
            raise httpx.HTTPStatusError("404", request=httpx.Request("GET", url), response=httpx.Response(404))
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(zips[url])
        return dest

    monkeypatch.setattr(db, "RAW_DIR", tmp_path / "raw")
    monkeypatch.setattr(loader, "CACHE_DIR", tmp_path / "cache")
    monkeypatch.setattr(loader, "CONGRESSES", [118])
    monkeypatch.setattr(loader, "BILL_TYPES", ["hjres", "sjres", "sres"])
    monkeypatch.setattr(loader, "fetch_to_file", fake_fetch_to_file)
    return requests


def _rows(table: str, cols: str = "*") -> list:
    return duckdb.sql(f"select {cols} from read_parquet('{db.raw_glob(table)}') order by 1").fetchall()


def test_load_lands_raw_xml_unchanged_and_one_row_per_entity(site):
    counts = loader.load(db.UNSHARDED)
    assert counts["govinfo_billstatus_bills"] == 2
    assert counts["govinfo_billstatus_files"] == 2  # readme.txt is not a bill file
    assert counts["govinfo_billstatus_laws"] == 1
    assert counts["govinfo_billstatus_sponsors"] == 2
    assert sorted(site) == sorted(loader.zip_url(118, t) for t in ("hjres", "sjres", "sres"))  # one request per zip
    stored = db.RAW_DIR / "govinfo_billstatus_xml/118/hjres/BILLSTATUS-118hjres26.xml.gz"
    assert gzip.decompress(stored.read_bytes()) == HJRES  # byte for byte
    ((path, size, sha),) = duckdb.sql(
        "select payload->>'path', payload->>'size_bytes', payload->>'sha256' "
        f"from read_parquet('{db.raw_glob('govinfo_billstatus_files')}') where record_key like '%hjres26%'"
    ).fetchall()
    assert path.endswith("hjres26.xml.gz") and int(size) == len(HJRES) and len(sha) == 64


def test_a_missing_zip_is_skipped_not_fatal(site):
    loader.load(db.UNSHARDED)  # sres has no zip in the fake site
    assert len(_rows("govinfo_billstatus_bills")) == 2


def test_rerun_is_idempotent(site):
    loader.load(db.UNSHARDED)
    stored = db.RAW_DIR / "govinfo_billstatus_xml/118/sjres/BILLSTATUS-118sjres32.xml.gz"
    before = (stored.read_bytes(), stored.stat().st_mtime_ns)
    first = {t: _rows(t, "record_key, payload") for t in parser.ALL_TABLES}
    loader.load(db.UNSHARDED)
    assert (stored.read_bytes(), stored.stat().st_mtime_ns) == before  # unchanged bytes are not rewritten
    assert {t: _rows(t, "record_key, payload") for t in parser.ALL_TABLES} == first


def test_shards_split_zips_without_overlap_and_cover_everything(site):
    owned = []
    for i in range(3):
        before = len(site)
        loader.load(db.Shard(i, 3))
        owned.append(set(site[before:]))
    all_urls = {loader.zip_url(118, t) for t in ("hjres", "sjres", "sres")}
    assert set().union(*owned) == all_urls
    assert sum(len(o) for o in owned) == len(all_urls)  # each zip is downloaded by exactly one shard
    assert len(_rows("govinfo_billstatus_bills")) == 2  # the three parts together hold every bill once


def test_a_server_error_fails_the_load_and_leaves_the_previous_landing(site, monkeypatch):
    loader.load(db.UNSHARDED)
    before = _rows("govinfo_billstatus_bills", "record_key")

    def boom(url, dest, *, max_age):
        raise httpx.HTTPStatusError("500", request=httpx.Request("GET", url), response=httpx.Response(500))

    monkeypatch.setattr(loader, "fetch_to_file", boom)
    with pytest.raises(httpx.HTTPStatusError):
        loader.load(db.UNSHARDED)
    assert _rows("govinfo_billstatus_bills", "record_key") == before


def test_nested_elements_never_stand_in_for_a_missing_bill_field():
    xml = (
        b"<billStatus><bill><number>1</number><congress>1</congress>"
        b"<actions><item><type>Veto</type><text>nested</text></item></actions></bill></billStatus>"
    )
    row = parser.parse_bill(xml, "f.xml")["bills"][0][1]
    assert row["bill_type"] is None  # the action's <type> is not the bill's
    assert row["title"] is None


def test_reserved_bill_with_billtype_and_billnumber_keeps_its_real_id():
    # The real 117th-Congress H.R. 2 ("Reserved for the Speaker"): this older export names the type and number
    # `billType` / `billNumber`. It used to parse to bill_id '117--None', colliding with the other reserved bills.
    rows = parser.parse_bill((FIXTURES / "BILLSTATUS-117hr2.xml").read_bytes(), "BILLSTATUS-117hr2.xml")
    ((_, row),) = rows["bills"]
    assert row["bill_id"] == "117-hr-2"
    assert (row["congress"], row["bill_type"], row["number"]) == ("117", "HR", "2")
    assert row["title"] == "Reserved for the Speaker."
    assert [k for k, _ in rows["actions"]] == ["117-hr-2#0", "117-hr-2#1"]


# ---- committees, subjects, related bills (#625) --------------------------------------------------------------
# Untrimmed copies of real 118th files: H.J.Res. 99 (a committee with a subcommittee), H.J.Res. 126 (a committee
# with three dated activities, two related bills) and S.J.Res. 9 (related bills carrying two relationship types).
HJRES99 = (FIXTURES / "BILLSTATUS-118hjres99.xml").read_bytes()
HJRES126 = (FIXTURES / "BILLSTATUS-118hjres126.xml").read_bytes()
SJRES9 = (FIXTURES / "BILLSTATUS-118sjres9.xml").read_bytes()
HR2 = (FIXTURES / "BILLSTATUS-117hr2.xml").read_bytes()


def test_committee_rows_and_their_activities_are_separate_long_tables():
    rows = parser.parse_bill(HJRES126, "f.xml")
    ((key, committee),) = rows["committees"]
    assert key == "118-hjres-126#0"
    assert (committee["system_code"], committee["name"], committee["chamber"], committee["committee_type"]) == (
        "hsba00",
        "Financial Services Committee",
        "House",
        "Standing",
    )
    assert committee["parent_system_code"] is None
    acts = [(p["activity"], p["activity_date"]) for _, p in rows["committee_activities"]]
    assert acts == [
        ("Reported By", "2024-07-30T17:44:28Z"),
        ("Markup By", "2024-04-17T18:44:00Z"),
        ("Referred To", "2024-04-05T13:00:50Z"),
    ]
    assert {p["system_code"] for _, p in rows["committee_activities"]} == {"hsba00"}


def test_subcommittee_is_its_own_row_pointing_at_its_parent():
    rows = parser.parse_bill(HJRES99, "f.xml")
    parent, sub = (p for _, p in rows["committees"])
    assert (parent["system_code"], parent["subposition"], parent["parent_system_code"]) == ("hsif00", None, None)
    assert (sub["system_code"], sub["name"], sub["subposition"]) == ("hsif14", "Health Subcommittee", 0)
    assert sub["parent_system_code"] == "hsif00"
    by_code = {p["system_code"]: p["activity_date"] for _, p in rows["committee_activities"]}
    assert by_code == {"hsif00": "2023-11-09T14:04:20Z", "hsif14": "2023-11-10T15:23:53Z"}


def test_legislative_subjects_are_one_row_each_and_the_policy_area_stays_on_the_bill():
    rows = parser.parse_bill(HJRES126, "f.xml")
    assert [(p["position"], p["name"]) for _, p in rows["subjects"]] == [
        (0, "Climate change and greenhouse gases"),
        (1, "Financial services and investments"),
        (2, "Legislative rules and procedure"),
    ]
    assert rows["subjects"][0][1]["update_date"] == "2024-10-31T19:27:45Z"
    assert rows["bills"][0][1]["policy_area"] == "Finance and Financial Sector"


def test_related_bills_carry_their_own_bill_and_relationship_types_separately():
    rows = parser.parse_bill(SJRES9, "f.xml")
    assert rows["related_bills"], "S.J.Res. 9 lists related bills"
    related = {(p["position"]): p for _, p in rows["related_bills"]}
    first = related[0]
    assert (first["related_congress"], first["related_bill_type"]) == ("118", "HRES")
    assert first["related_number"] == "614" and first["title"] and first["latest_action_date"]
    rels = [
        (p["related_position"], p["position"], p["relationship_type"], p["identified_by"])
        for _, p in rows["related_bill_relationships"]
    ]
    assert (0, 0, "Procedurally related", "House") in rels
    assert (0, 1, "Related bill", "House") in rels
    assert (1, 0, "Identical bill", "CRS") in rels
    assert len(rels) > len(rows["related_bills"])  # a bill with two relationship types gets two rows
    hj = parser.parse_bill(HJRES126, "f.xml")
    assert [(p["related_bill_type"], p["related_number"]) for _, p in hj["related_bills"]] == [
        ("HJRES", "125"),
        ("HJRES", "124"),
    ]
    assert [p["relationship_type"] for _, p in hj["related_bill_relationships"]] == ["Related bill"] * 2


def test_older_layout_with_empty_wrappers_yields_no_rows_and_no_error():
    # 117th H.R. 2 nests empty lists as <committees><billCommittees/></committees> and
    # <subjects><billSubjects><legislativeSubjects/></billSubjects></subjects>; the wrapper is not an item.
    rows = parser.parse_bill(HR2, "f.xml")
    for key in ("committees", "committee_activities", "subjects", "related_bills", "related_bill_relationships"):
        assert rows[key] == []


def test_older_layout_wrapper_is_looked_through():
    # Synthetic (no real older file has entries): the same items one level down inside the older wrappers.
    xml = (
        b"<billStatus><bill><billNumber>9</billNumber><billType>HR</billType><congress>117</congress>"
        b"<committees><billCommittees><item><systemCode>hsju00</systemCode><name>Judiciary</name></item></billCommittees>"
        b"</committees><subjects><billSubjects><legislativeSubjects><item><name>Taxation</name></item>"
        b"</legislativeSubjects></billSubjects></subjects></bill></billStatus>"
    )
    rows = parser.parse_bill(xml, "f.xml")
    assert [p["system_code"] for _, p in rows["committees"]] == ["hsju00"]
    assert [p["name"] for _, p in rows["subjects"]] == ["Taxation"]


def test_new_entity_row_keys_are_unique_across_every_fixture():
    for xml in (HJRES99, HJRES126, SJRES9, HR2):
        for key in ("committees", "committee_activities", "subjects", "related_bills", "related_bill_relationships"):
            keys = [k for k, _ in parser.parse_bill(xml, "f.xml")[key]]
            assert len(keys) == len(set(keys)), key
