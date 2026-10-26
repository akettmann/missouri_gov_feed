# ruff: noqa: E501  (inline XML fixtures)
import gzip
from datetime import date

import duckdb
import pytest
import structlog.testing

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
        ("251-GRP1.XML", ("other", "GRP1")),
        ("191-HJR.XML", ("other", "HJR")),
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


def test_other_kinds_are_not_parsed():
    grp = b"<ROOT><BillInformation><BillNumber>GRP1</BillNumber><Title><ShortTitle>X</ShortTitle></Title></BillInformation></ROOT>"
    assert not any(_rows("191-GRP1.XML", grp, "191").values())
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


def test_land_file_does_not_rewrite_an_unchanged_gzip(raw_dir, monkeypatch):
    xml = BILL + b"\n"
    row = loader._land_file("251", "251-HB10.XML", xml, "https://x/251.zip#251-HB10.xml")
    writes = []
    monkeypatch.setattr(loader, "write_atomic", lambda *args: writes.append(args))
    loader._land_file("251", "251-HB10.XML", xml, row.source_url)
    assert writes == []  # same bytes: left alone
    loader._land_file("251", "251-HB10.XML", xml + b"<!-- changed -->", row.source_url)
    assert len(writes) == 1  # different bytes: rewritten


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


# ---- values that are not what the column type says ---------------------------------------------------------------


def test_amendment_sort_value_is_text_not_dropped():
    xml = b"<R><BillInformation><Amendment><AmendmentDescription>HA 1</AmendmentDescription><AmendmentSortValue>0507HH</AmendmentSortValue></Amendment></BillInformation></R>"
    (am,) = _rows("251-HB1.XML", xml)[p.BillAmendment]
    assert am.sort_value == "0507HH"


def test_unconvertible_values_are_logged_not_silently_dropped():
    xml = b"<R><BillInformation><Action><Description>x</Description><ActivitySequence>12a</ActivitySequence><PubDate>not a date</PubDate></Action></BillInformation></R>"
    with structlog.testing.capture_logs() as logs:
        (a,) = _rows("251-HB1.XML", xml)[p.BillAction]
    assert (a.activity_sequence, a.pub_date) == (None, None)
    warned = {(e["event"], e["field"], e["value"]) for e in logs if e["log_level"] == "warning"}
    assert warned == {
        ("mo_house.value_not_integer", "ActivitySequence", "12a"),
        ("mo_house.value_not_date", "PubDate", "not a date"),
    }


def test_missing_or_blank_numbers_and_dates_do_not_warn():
    xml = b"<R><BillInformation><Action><Description>x</Description><ActivitySequence> </ActivitySequence></Action></BillInformation></R>"
    with structlog.testing.capture_logs() as logs:
        _rows("251-HB1.XML", xml)
    assert logs == []


def test_empty_elements_are_null_not_empty_strings():
    bill = b"<R><BillInformation><BillNumber>HB1</BillNumber><Title><ShortTitle></ShortTitle><LongTitle> </LongTitle></Title></BillInformation></R>"
    (b,) = _rows("251-HB1.XML", bill)[p.Bill]
    assert (b.bill_number, b.short_title, b.long_title) == ("HB1", None, None)
    member = b"<R><RepresentativeData><RepresentativeInfo><DistrictNum>001</DistrictNum><LastName>Farnan</LastName><Biography/></RepresentativeInfo></RepresentativeData></R>"
    (m,) = _rows("251-001.XML", member)[p.Member]
    assert (m.last_name, m.biography) == ("Farnan", None)


def test_a_repaired_document_is_reported_with_its_file_name():
    with structlog.testing.capture_logs() as logs:
        root = p.parse_xml(b"<R><a>x</R>", "251-HB1.XML")
    assert root is not None
    (event,) = [e for e in logs if e["event"] == "mo_house.xml_recovered"]
    assert event["file"] == "251-HB1.XML"
    assert event["errors"] >= 1
    with structlog.testing.capture_logs() as logs:
        p.parse_xml(b"<R><a>x</a></R>", "251-HB1.XML")
    assert logs == []


# ---- fields that used to be skipped -------------------------------------------------------------------------------

FULL_BILL = b"""<ROOT><BillInformation><BillNumber>HB5</BillNumber>
<SubstitutedBy><ParentBillString>HB 1</ParentBillString><ParentBillLink>http://x/hb1</ParentBillLink></SubstitutedBy>
<SummarySheet><SummarySheetLink>http://x/sheet.pdf</SummarySheetLink></SummarySheet>
<PastSessionAppropriationBill>HB 2002</PastSessionAppropriationBill>
<BillSummary><DocumentName>Introduced</DocumentName><SummaryTextLink>http://x/s1.pdf</SummaryTextLink><VersionTypeCode>I</VersionTypeCode><LRNumber>0001H.01I</LRNumber><BillVersionSort>1</BillVersionSort></BillSummary>
<BillSummary><DocumentName>Perfected</DocumentName><SummaryTextLink>http://x/s2.pdf</SummaryTextLink></BillSummary>
<FiscalNote><FiscalNoteLink>http://x/fn1.pdf</FiscalNoteLink></FiscalNote>
<FiscalNotes><FiscalNoteLink>http://x/fn2.pdf</FiscalNoteLink><FiscalNoteLink>http://x/fn3.pdf</FiscalNoteLink></FiscalNotes>
<Witness><WitnessFormsLink>http://x/w1</WitnessFormsLink><WitnessFormLinkDescription>Forms for HB 5</WitnessFormLinkDescription></Witness>
<Witness><WitnessFormsLink>http://x/w2</WitnessFormsLink></Witness>
<Witness/>
<BillText><DocumentName>Introduced</DocumentName><SummaryTextLink>http://x/ts.pdf</SummaryTextLink><Map><MapLink>http://x/map.pdf</MapLink></Map></BillText>
<Amendment><AmendmentDescription>HA 1</AmendmentDescription><Map><MapLink>http://x/amap.pdf</MapLink></Map></Amendment>
</BillInformation></ROOT>"""


def test_bill_summaries_fiscal_notes_witness_links_and_maps_become_rows():
    out = _rows("251-HB5.XML", FULL_BILL)
    (b,) = out[p.Bill]
    assert (b.substituted_by, b.substituted_by_link) == ("HB 1", "http://x/hb1")
    assert (b.summary_sheet_link, b.past_session_appropriation_bill) == ("http://x/sheet.pdf", "HB 2002")
    assert [
        (s.summary_index, s.document_name, s.summary_text_link, s.version_type_code, s.lr_number, s.version_sort)
        for s in out[p.BillSummary]
    ] == [
        (1, "Introduced", "http://x/s1.pdf", "I", "0001H.01I", 1),
        (2, "Perfected", "http://x/s2.pdf", None, None, None),
    ]
    assert [(f.fiscal_note_index, f.element, f.fiscal_note_link) for f in out[p.BillFiscalNote]] == [
        (1, "FiscalNote", "http://x/fn1.pdf"),
        (2, "FiscalNotes", "http://x/fn2.pdf"),
        (3, "FiscalNotes", "http://x/fn3.pdf"),
    ]
    assert [(w.witness_forms_link, w.witness_form_link_description) for w in out[p.BillWitness]] == [
        ("http://x/w1", "Forms for HB 5"),
        ("http://x/w2", None),
    ]  # the empty <Witness/> between them and after them is not a row (#384)
    assert [w.witness_index for w in out[p.BillWitness]] == [1, 2]
    (t,) = out[p.BillText]
    assert (t.summary_text_link, t.map_link) == ("http://x/ts.pdf", "http://x/map.pdf")
    assert out[p.BillAmendment][0].map_link == "http://x/amap.pdf"


def test_calendar_handler_upcoming_hearing_chair_and_list_notice():
    cal = b"""<ROOT><NOTICE>Subject to change</NOTICE><DailyCalendar><SessionDay><DateString>Mon</DateString></SessionDay><Calendar><CalendarName>Perfection</CalendarName>
    <BillInfo><BillType>HB</BillType><BillNumber>4</BillNumber><SponsorLastName>Smith</SponsorLastName><SponsorDistrict>001</SponsorDistrict>
    <HandlerFirstName>Ann</HandlerFirstName><HandlerLastName>Lee</HandlerLastName><HandlerDistrict>009</HandlerDistrict><HandlerChamber>H</HandlerChamber></BillInfo>
    <BillInfo><BillType>HB</BillType><BillNumber>5</BillNumber></BillInfo></Calendar></DailyCalendar></ROOT>"""
    out = _rows("251-CALENDARLIST.XML", cal)
    assert [
        (c.bill_number, c.handler_first_name, c.handler_last_name, c.handler_district, c.handler_chamber)
        for c in out[p.CalendarBill]
    ] == [
        (4, "Ann", "Lee", 9, "H"),
        (5, None, None, None, None),
    ]
    assert [n.notice for n in out[p.ListNotice]] == ["Subject to change"]
    hearing = b"""<ROOT><NOTICE>Hearing notice</NOTICE><HearingInfo><HearingID>1</HearingID><CommitteeChairFirstName>Bo</CommitteeChairFirstName>
    <CommitteeChairLastName>Ray</CommitteeChairLastName><CommitteeChairDistrict>12</CommitteeChairDistrict><CommitteeChairChamber>H</CommitteeChairChamber></HearingInfo></ROOT>"""
    out = _rows("251-UPCOMINGHEARINGLIST.XML", hearing)
    assert [
        (h.chair_first_name, h.chair_last_name, h.chair_district, h.chair_chamber) for h in out[p.UpcomingHearing]
    ] == [("Bo", "Ray", 12, "H")]
    assert [n.notice for n in out[p.ListNotice]] == ["Hearing notice"]
    assert not _rows("251-BILLLIST.XML", b"<ROOT/>")[p.ListNotice]


# ---- SenateActList: the House's actions on Senate bills ---------------------------------------------------------

SENATE_ACT = b"""<ROOT><SenateBillsWithHouseActions>
<BillInformation><BillNumber>SB727</BillNumber><CurrentBillString>SS#2 SCS SB 727</CurrentBillString><SubstitutedBy/>
<CurrentVersionTypeCode>T</CurrentVersionTypeCode><CurrentLRNumber>3329S.24T</CurrentLRNumber><ShortTitle>EDUCATION</ShortTitle><LongTitle>Creates provisions</LongTitle>
<ProposedEffectiveDate>2024-08-28T00:00:00</ProposedEffectiveDate><EffectiveDateVaries>1</EffectiveDateVaries>
<SponsorName>Koenig, Andrew</SponsorName><SponsorDistrict>15</SponsorDistrict><SponsorLink>https://senate.mo.gov/Senators/Member/15</SponsorLink>
<LastAction>04/24/2024 - Signed by House Speaker (H)</LastAction>
<GovernorLastAction><GovernorLastAction><GovernorAction>07/01/2024 - Signed</GovernorAction><GovernorsVetoLetter/></GovernorLastAction></GovernorLastAction>
<Action><Link>http://x/b?bill=SB727 </Link><Description>Reported to the House and First Read (H)</Description><Guid>1</Guid><ActivitySequence>600</ActivitySequence><PubDate>2024-03-14</PubDate></Action>
<Action><Link>http://x/b</Link><Description>Reported Do Pass (H)</Description><Guid>2</Guid><PubDate>2024-04-02</PubDate><RollCall><TotalYes>6</TotalYes><TotalNo>2</TotalNo><TotalPresent>0</TotalPresent></RollCall></Action>
<BillSummary><DocumentName>Truly Agreed</DocumentName><SummaryTextLink>http://x/sum.pdf</SummaryTextLink></BillSummary>
<BillText><DocumentName>Truly Agreed</DocumentName><RollCalls><RollCall><RollCallNumber>3</RollCallNumber><RollCallPDF>http://x/bills241/rollcalls/060.003.pdf</RollCallPDF></RollCall></RollCalls></BillText>
<Amendment><AmendmentDescription>HA 1</AmendmentDescription><AmendmentSortValue>0507HH</AmendmentSortValue></Amendment>
<Witness><WitnessFormsLink>http://x/w</WitnessFormsLink></Witness>
</BillInformation>
<BillInformation><BillNumber>SB9</BillNumber><ShortTitle>OTHER</ShortTitle>
<Action><Description>Read Second Time (H)</Description><Guid>3</Guid><PubDate>2024-03-18</PubDate></Action></BillInformation>
</SenateBillsWithHouseActions></ROOT>"""


def test_senate_act_list_rows_reuse_the_bill_shape_in_their_own_tables():
    out = _rows("241-SENATEACTLIST.XML", SENATE_ACT, "241")
    sa = p.SENATE_ACT_TYPES
    bills = out[sa[p.Bill]]
    assert [(b.bill, b.bill_number, b.short_title, b.long_title) for b in bills] == [
        ("SB727", "SB727", "EDUCATION", "Creates provisions"),
        ("SB9", "SB9", "OTHER", None),
    ]
    b = bills[0]
    assert (b.session_code, b.file_name, b.current_lr_number) == ("241", "241-SENATEACTLIST.XML", "3329S.24T")
    assert b.proposed_effective_date == date(2024, 8, 28)
    assert (b.sponsor_name, b.sponsor_district, b.sponsor_link) == (
        "Koenig, Andrew",
        15,
        "https://senate.mo.gov/Senators/Member/15",
    )
    assert (b.current_version_type_code, b.effective_date_varies) == ("T", "1")
    assert (b.governor_action, b.governors_veto_letter) == ("07/01/2024 - Signed", None)
    actions = out[sa[p.BillAction]]
    assert [(a.bill, a.action_index, a.description, a.rollcall_total_yes) for a in actions] == [
        ("SB727", 1, "Reported to the House and First Read (H)", None),
        ("SB727", 2, "Reported Do Pass (H)", 6),
        ("SB9", 1, "Read Second Time (H)", None),
    ]
    assert actions[0].link == "http://x/b?bill=SB727"
    assert [(s.bill, s.document_name) for s in out[sa[p.BillSummary]]] == [("SB727", "Truly Agreed")]
    assert [(r.bill, r.parent_kind, r.rollcall_pdf[-11:]) for r in out[sa[p.BillRollCall]]] == [
        ("SB727", "text", "060.003.pdf")
    ]
    assert [(a.bill, a.sort_value) for a in out[sa[p.BillAmendment]]] == [("SB727", "0507HH")]
    assert [w.bill for w in out[sa[p.BillWitness]]] == ["SB727"]
    # the sponsor is on the bill row; the twin tables for Sponsor/SubjectIndex children would stay empty (#384)
    assert p.BillSponsor not in sa and p.BillSubject not in sa
    assert (out[sa[p.Bill]][0].sponsor_name, out[sa[p.Bill]][0].sponsor_district) == ("Koenig, Andrew", 15)
    assert not {"mo_house_xml_senate_act_sponsors", "mo_house_xml_senate_act_subjects"} & {t.TABLE for t in p.ROW_TYPES}
    # nothing leaks into the House bill tables that staging reads
    assert not any(out[t] for t in p.BILL_ROW_TYPES)


def test_senate_act_tables_are_distinct_and_typed(raw_dir):
    names = [t.TABLE for t in p.ROW_TYPES]
    assert len(names) == len(set(names))
    assert p.SENATE_ACT_TYPES[p.BillAction].TABLE == "mo_house_xml_senate_act_actions"
    assert p.SENATE_ACT_TYPES[p.Bill].TABLE == "mo_house_xml_senate_act_bills"
    _land(raw_dir, db.UNSHARDED, [("241", "241-SENATEACTLIST.XML", SENATE_ACT)])
    counts = p.parse_landed(db.UNSHARDED)
    assert (counts["mo_house_xml_senate_act_bills"], counts["mo_house_xml_senate_act_actions"]) == (2, 3)
    assert counts["mo_house_xml_bills"] == 0
    sql = f"describe select * from read_parquet('{db.raw_glob('mo_house_xml_senate_act_actions')}')"
    cols = {r[0]: r[1] for r in duckdb.sql(sql).fetchall()}
    assert cols["bill"] == "VARCHAR"
    assert cols["pub_date"] == "DATE"
