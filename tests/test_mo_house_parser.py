# ruff: noqa: E501  (inline XML fixtures)
import gzip
from datetime import date

import duckdb
import pytest

from mogov import db
from mogov.loaders import mo_house as loader
from mogov.parsers import mo_house as p


def _links(data: bytes, tag: str) -> list[str]:
    root = p.parse_xml(data)
    return [] if root is None else p.links(root, tag)


# ---- link extraction (same parsed tree the rows come from) ----------------------------------------------------


def test_links_plain_elements():
    xml = (
        b"<BillList><Bill><BillXMLLink>http://x/a.XML</BillXMLLink></Bill>"
        b"<Bill><BillXMLLink> http://x/b.XML </BillXMLLink></Bill></BillList>"
    )
    assert _links(xml, "BillXMLLink") == ["http://x/a.XML", "http://x/b.XML"]


def test_links_decode_entities():
    xml = b"<R><RollCallPDF>http://x/a.pdf?p=1&amp;q=2</RollCallPDF></R>"
    assert _links(xml, "RollCallPDF") == ["http://x/a.pdf?p=1&q=2"]


def test_links_elements_with_attributes_or_namespace():
    xml = b'<R xmlns:h="urn:h"><BillXMLLink type="x">http://x/a</BillXMLLink><h:BillXMLLink>http://x/b</h:BillXMLLink></R>'
    assert _links(xml, "BillXMLLink") == ["http://x/a", "http://x/b"]
    ns = b'<R xmlns="urn:h"><RollCallPDF>http://x/c.pdf</RollCallPDF></R>'
    assert _links(ns, "RollCallPDF") == ["http://x/c.pdf"]


def test_links_cdata_and_comments():
    xml = b"<R><!-- <BillXMLLink>http://x/old</BillXMLLink> --><BillXMLLink><![CDATA[http://x/new?a=1&b=2]]></BillXMLLink></R>"
    assert _links(xml, "BillXMLLink") == ["http://x/new?a=1&b=2"]


def test_links_ignore_empty_and_non_xml():
    assert _links(b"<R><BillXMLLink/><BillXMLLink>  </BillXMLLink></R>", "BillXMLLink") == []
    assert _links(b"<!DOCTYPE html><html>error</html", "BillXMLLink") == []
    assert _links(b"", "BillXMLLink") == []


def test_parser_does_not_resolve_entities_or_touch_the_network():
    xml = b'<!DOCTYPE r [<!ENTITY e SYSTEM "file:///etc/passwd">]><R><BillXMLLink>x&e;y</BillXMLLink></R>'
    assert "root:" not in "".join(_links(xml, "BillXMLLink"))


# ---- classify --------------------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("name", "expected"),
    [
        ("251-001.XML", ("member", "001")),
        ("251-hb10.xml", ("bill", "HB10")),
        ("251-HCB1.XML", ("bill", "HCB1")),
        ("251-SESSIONLIST.XML", ("list", "SESSIONLIST")),
        ("251-UpcomingHearingList.xml", ("list", "UPCOMINGHEARINGLIST")),
        ("251-GRP1.XML", None),
    ],
)
def test_classify(name, expected):
    assert p.classify(name) == expected


# ---- documents -> typed rows -----------------------------------------------------------------------------------

BILL = b"""<ROOT><BillInformation>
<BillNumber>HB10</BillNumber><CurrentBillString>HCS HB 10</CurrentBillString><SubstitutedBy/>
<Title><ShortTitle>APPROPRIATIONS</ShortTitle><LongTitle>Appropriates money</LongTitle></Title>
<ProposedEffectiveDate>2025-08-28</ProposedEffectiveDate>
<GovernorLastAction><GovernorAction>06/30/2025 - Vetoed</GovernorAction><GovernorsVetoLetter>http://x/vl.pdf</GovernorsVetoLetter></GovernorLastAction>
<LastAction>09/10/2025 - Failed (H)</LastAction>
<Action><Link>http://x/bill?a=1&amp;b=2 </Link><Description>Introduced (H)</Description><Guid>11</Guid>
 <ActivitySequence>100</ActivitySequence><PubDate>2025-02-19</PubDate><HouseJournalStartPage>680</HouseJournalStartPage></Action>
<Action><Link>http://x/bill</Link><Description>Third Read</Description><Guid>12</Guid><PubDate>2025-03-01</PubDate>
 <RollCall><TotalYes>110</TotalYes><TotalNo>40</TotalNo><TotalPresent>2</TotalPresent></RollCall></Action>
<Sponsor><SponsorType>Sponsor</SponsorType><FullName>Dirk Deaton</FullName><District>159</District></Sponsor>
<Sponsor><SponsorType>Co-Sponsor</SponsorType><FullName>A B</FullName><District>097</District><CoSponsorEntryDate>2025-02-20</CoSponsorEntryDate></Sponsor>
<BillText><BillTextLink>http://x/t1.pdf</BillTextLink><LRNumber>0010H.01I</LRNumber><DocumentName>Introduced</DocumentName>
 <VersionTypeCode>I</VersionTypeCode><BillVersionSort>1</BillVersionSort></BillText>
<BillText><DocumentName>Perfected</DocumentName>
 <RollCalls><RollCall><RollCallNumber>7</RollCallNumber><RollCallPDF>http://x/bills251/rollcalls/048.007.pdf</RollCallPDF>
 <SessionDay>48</SessionDay><TotalYes>1</TotalYes><TotalNo>2</TotalNo><TotalPresent>3</TotalPresent></RollCall>
 <RollCall><RollCallPDF>http://x/bills251/rollcalls/049.001.pdf</RollCallPDF></RollCall></RollCalls></BillText>
<Amendment><AmendmentDescription>HA 1</AmendmentDescription><AmendmentText>text</AmendmentText><Sponsor>Smith</Sponsor><Status>A</Status>
 <RollCalls><RollCall><RollCallPDF>http://x/bills251/rollcalls/050.001.pdf</RollCallPDF></RollCall></RollCalls></Amendment>
<SubjectIndex><SubjectID>5</SubjectID><SubjectName>APPROPRIATIONS</SubjectName></SubjectIndex>
<Hearings><CommitteeName>Budget</CommitteeName><NoticeDate>2025-03-26</NoticeDate><NoticeTime>1900-01-01T08:00:00</NoticeTime><Location>HR 4</Location></Hearings>
</BillInformation></ROOT>"""


def _rows(name: str, data: bytes, session: str = "251"):
    root = p.parse_xml(data)
    assert root is not None
    rows = list(p.parse_document(session, name, root))
    return {t: [r for r in rows if type(r) is t] for t in p.ROW_TYPES}


def test_bill_document_emits_a_bill_row_and_child_rows():
    out = _rows("251-HB10.XML", BILL)
    (bill,) = out[p.Bill]
    assert (bill.session_code, bill.file_name, bill.bill) == ("251", "251-HB10.XML", "HB10")
    assert bill.short_title == "APPROPRIATIONS"
    assert bill.proposed_effective_date == date(2025, 8, 28)
    assert bill.governor_action == "06/30/2025 - Vetoed"
    assert bill.substituted_by is None  # empty element
    a1, a2 = out[p.BillAction]
    assert (a1.action_index, a1.link, a1.guid, a1.activity_sequence, a1.pub_date) == (
        1,
        "http://x/bill?a=1&b=2",
        "11",
        100,
        date(2025, 2, 19),
    )
    assert a1.rollcall_total_yes is None
    assert (a2.rollcall_total_yes, a2.rollcall_total_no, a2.rollcall_total_present) == (110, 40, 2)
    assert [(s.sponsor_type, s.full_name, s.district) for s in out[p.BillSponsor]] == [
        ("Sponsor", "Dirk Deaton", 159),
        ("Co-Sponsor", "A B", 97),
    ]
    assert out[p.BillSponsor][1].cosponsor_entry_date == date(2025, 2, 20)
    assert [t.document_name for t in out[p.BillText]] == ["Introduced", "Perfected"]
    assert [(r.parent_kind, r.parent_name, r.rollcall_number, r.rollcall_pdf[-11:]) for r in out[p.BillRollCall]] == [
        ("text", "Perfected", 7, "048.007.pdf"),
        ("text", "Perfected", None, "049.001.pdf"),
        ("amendment", "HA 1", None, "050.001.pdf"),
    ]
    assert [(s.subject_id, s.subject_name) for s in out[p.BillSubject]] == [("5", "APPROPRIATIONS")]
    assert [(h.committee_name, h.notice_date) for h in out[p.BillHearing]] == [("Budget", date(2025, 3, 26))]
    assert len(out[p.BillAmendment]) == 1


def test_member_document_emits_member_committees_and_counties_but_no_contact_details():
    xml = b"""<ROOT><RepresentativeData><RepresentativeInfo>
    <PhotoLink>https://images.house.mo.gov/MemberPhoto.aspx?id=2354</PhotoLink><LastName>Farnan</LastName><FirstName>Jeff</FirstName>
    <DistrictNum>001</DistrictNum><Party>Republican</Party><YearElected>2022</YearElected><Hometown>Stanberry</Hometown>
    <Counties><County><CountyName>Atchison</CountyName></County><County><CountyName>Holt</CountyName></County></Counties>
    <Committees><Committee><CommitteeName>Agriculture</CommitteeName><CommitteePosition>Chair</CommitteePosition></Committee></Committees>
    <PhoneNumber>573-555-0100</PhoneNumber><EmailAddress>x@house.mo.gov</EmailAddress>
    </RepresentativeInfo></RepresentativeData></ROOT>"""
    out = _rows("251-001.XML", xml)
    (m,) = out[p.Member]
    assert (m.district, m.district_number, m.last_name, m.year_elected, m.years_served) == (
        "001",
        1,
        "Farnan",
        2022,
        None,
    )
    assert m.photo_link.endswith("id=2354")
    assert [(c.committee_name, c.committee_position) for c in out[p.MemberCommittee]] == [("Agriculture", "Chair")]
    assert [c.county_name for c in out[p.MemberCounty]] == ["Atchison", "Holt"]
    assert not {"phone_number", "email_address"} & set(vars(m))


def test_vacant_member_file_has_no_last_name():
    xml = b"<ROOT><RepresentativeData><RepresentativeInfo><DistrictNum>002</DistrictNum><VacantName>Vacant</VacantName></RepresentativeInfo></RepresentativeData></ROOT>"
    (m,) = _rows("251-002.XML", xml)[p.Member]
    assert m.last_name is None
    assert m.vacant_name == "Vacant"


def test_list_documents_emit_one_row_per_item():
    sessions = b"""<ROOT><Session><ID>254</ID><Name>2025 2nd Extraordinary Session</Name><SessionYear>2025</SessionYear>
    <SessionCode>S2</SessionCode><GeneralAssembly>103rd</GeneralAssembly><SessionOfGeneralAssembly>2nd</SessionOfGeneralAssembly></Session>
    <Session><ID>251</ID><Name>2025 Regular Session</Name><SessionYear>2025</SessionYear></Session></ROOT>"""
    rows = _rows("254-SESSIONLIST.XML", sessions, "254")[p.Session]
    assert [(r.session_code, r.session_id, r.name, r.session_year, r.session_type) for r in rows] == [
        ("254", "254", "2025 2nd Extraordinary Session", 2025, "S2"),
        ("254", "251", "2025 Regular Session", 2025, None),
    ]
    committees = b"""<ROOT><Committee><ID>3029</ID><Type>Admin</Type><Name>Accounts</Name><CommitteeMembers>
    <CommitteeMember><MemberName>Peggy McGaugh</MemberName><MemberDistrict>007</MemberDistrict><PositionName>Chair</PositionName><Chamber>H</Chamber></CommitteeMember>
    <CommitteeMember><MemberName>Richard West</MemberName><MemberDistrict>102</MemberDistrict><PositionName>Member</PositionName><Chamber>H</Chamber></CommitteeMember>
    </CommitteeMembers></Committee><Committee><ID>9</ID><Name>Empty</Name></Committee></ROOT>"""
    out = _rows("251-COMMITTEELIST.XML", committees)
    assert [(c.committee_id, c.name) for c in out[p.Committee]] == [("3029", "Accounts"), ("9", "Empty")]
    assert [(m.committee_id, m.member_name, m.member_district, m.position_name) for m in out[p.CommitteeMember]] == [
        ("3029", "Peggy McGaugh", 7, "Chair"),
        ("3029", "Richard West", 102, "Member"),
    ]
    bills = b"<ROOT><BillXML><BillType>HB</BillType><BillNumber>2</BillNumber><SessionYear>2025</SessionYear><SessionCode>R</SessionCode><BillXMLLink>http://x/251-HB2.xml</BillXMLLink></BillXML><BillXML><BillType>HB</BillType><BillNumber>3</BillNumber></BillXML></ROOT>"
    assert [(b.bill_type, b.bill_number, b.xml_link) for b in _rows("251-BILLLIST.XML", bills)[p.BillListEntry]] == [
        ("HB", 2, "http://x/251-HB2.xml"),
        ("HB", 3, None),
    ]


def test_unparsed_kinds_emit_nothing():
    assert not any(_rows("251-SENATEACTLIST.XML", b"<ROOT><SenateBillsWithHouseActions/></ROOT>").values())


# ---- landing files unchanged, state row, parse from disk ---------------------------------------------------


@pytest.fixture
def raw_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(db, "RAW_DIR", tmp_path)
    return tmp_path


def test_land_file_writes_gzip_unchanged_and_is_idempotent(raw_dir):
    xml = BILL + b"\n"
    row = loader._land_file("251", "251-HB10.XML", xml, "https://documents.house.mo.gov/xml/251.zip#251-HB10.xml")
    dest = raw_dir / row.path
    assert row.path == "mo_house_xml/251/251-HB10.XML.gz"
    assert gzip.decompress(dest.read_bytes()) == xml  # byte for byte
    assert (row.kind, row.item, row.size_bytes) == ("bill", "HB10", len(xml))
    first = dest.read_bytes()
    again = loader._land_file("251", "251-HB10.XML", xml, row.source_url)
    assert dest.read_bytes() == first
    assert again.sha256 == row.sha256


def _land(raw_dir, shard, files):
    with db.TableSink(shard, tables=[p.XmlFile]) as sink:
        for code, name, xml in files:
            sink.add(loader._land_file(code, name, xml, f"https://x/{code}.zip#{name}"))


def test_parse_landed_writes_typed_tables_for_owned_sessions_only(raw_dir):
    files = [("251", "251-HB10.XML", BILL), ("241", "241-HB10.XML", BILL)]
    one, two = db.Shard(0, 2), db.Shard(1, 2)
    owned = [f for f in files if one.owns(f[0])]
    assert len(owned) == 1, "test needs the two session codes on different shards"
    _land(raw_dir, one, owned)
    counts = p.parse_landed(one)
    assert counts[p.Bill.TABLE] == 1
    assert counts[p.BillAction.TABLE] == 2
    assert counts[p.Member.TABLE] == 0  # published even when empty
    sql = f"select session_code, bill, proposed_effective_date, short_title from read_parquet('{db.raw_glob(p.Bill.TABLE)}')"
    assert duckdb.sql(sql).fetchall() == [(owned[0][0], "HB10", date(2025, 8, 28), "APPROPRIATIONS")]
    assert p.landed_files(two) == []


def test_typed_columns_survive_the_round_trip(raw_dir):
    _land(raw_dir, db.UNSHARDED, [("251", "251-HB10.XML", BILL)])
    p.parse_landed(db.UNSHARDED)
    cols = {
        r[0]: r[1]
        for r in duckdb.sql(f"describe select * from read_parquet('{db.raw_glob(p.BillAction.TABLE)}')").fetchall()
    }
    assert cols["pub_date"] == "DATE"
    assert cols["action_index"] == "BIGINT"
    assert cols["rollcall_total_yes"] == "BIGINT"
    assert cols["description"] == "VARCHAR"
