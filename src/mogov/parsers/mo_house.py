"""Parser for the Missouri House XML exports landed by `mogov.loaders.mo_house`.

The loader stores every XML file unchanged as gzip and records it in `mo_house_xml_files`. This module reads those
files with lxml (hardened settings, via `mogov.xmlparse`), walks each document and emits typed rows per entity:

- member document   -> member row + committee-post and county child rows
- bill document     -> bill row + actions (with roll-call totals), sponsors, texts, amendments, roll calls,
                       subjects, hearings
- SessionList       -> one row per session
- CommitteeList     -> one row per committee + one per committee member
- BillList / MemberList / UpcomingHearingList / CalendarList -> one row per listed item (+ the list's NOTICE)
- SenateActList      -> the same typed rows as a bill document for every Senate bill the House acted on, in
                       `mo_house_xml_senate_act_*` tables (a `bill` column ties child rows to their bill)

Elements are selected by local name, so namespaces and attributes don't matter. Empty elements are NULL. A
member's contact details (email, phone, address, assistant) are deliberately not carried into rows; they stay in
the raw gzip. The odd GRP* files (and any other file that is not a member, bill or list) are landed with the
rest but never parsed: kind 'other' (see docs/sources.md).
"""

import gzip
import re
from collections.abc import Callable, Iterator
from dataclasses import dataclass, fields, make_dataclass
from datetime import date, datetime
from typing import ClassVar

from lxml import etree

from mogov import db, obs, xmlparse

log = obs.get_logger(__name__)

KIND_MEMBER, KIND_BILL, KIND_LIST, KIND_OTHER = "member", "bill", "list", "other"
BILL_ITEM = re.compile(r"^H[A-Z]*\d+$")


def classify(file_name: str) -> tuple[str, str]:
    """(kind, item) of a House XML file name such as 251-HB10.XML, 251-001.XML or 251-SESSIONLIST.XML; kind
    'other' for files that are not members, bills or lists (e.g. 191-GRP1.XML): landed, never parsed."""
    stem = file_name.upper().removesuffix(".XML")
    _, _, item = stem.partition("-")
    if item.isdigit():
        return KIND_MEMBER, item
    if item.endswith("LIST"):
        return KIND_LIST, item
    if BILL_ITEM.match(item):
        return KIND_BILL, item
    return KIND_OTHER, item


# ---- element helpers --------------------------------------------------------------------------------------


def _local(el: etree._Element) -> str | None:
    return etree.QName(el).localname if isinstance(el.tag, str) else None


def children(el: etree._Element | None, name: str) -> list[etree._Element]:
    return [c for c in el if _local(c) == name] if el is not None else []


def child(el: etree._Element | None, name: str) -> etree._Element | None:
    return next((c for c in el if _local(c) == name), None) if el is not None else None


def text(el: etree._Element | None, name: str) -> str | None:
    """Stripped text of the first <name> child; None when missing or blank."""
    c = child(el, name)
    if c is None:
        return None
    return "".join(c.itertext()).strip() or None


def integer(el: etree._Element | None, name: str) -> int | None:
    """Integer value of the first <name> child; None when missing or blank. A value that is present but not an
    integer is also None, but logged (a typed column must not silently drop data)."""
    value = text(el, name)
    if value is None:
        return None
    try:
        return int(value)
    except ValueError:
        log.warning("mo_house.value_not_integer", field=name, value=value)
        return None


def day(el: etree._Element | None, name: str) -> date | None:
    """Date of the first <name> child (an ISO date or datetime); None when missing, blank or (logged) unreadable."""
    value = text(el, name)
    if value is None:
        return None
    try:
        return date.fromisoformat(value[:10])
    except ValueError:
        log.warning("mo_house.value_not_date", field=name, value=value)
        return None


def parse_xml(data: bytes, file: str | None = None) -> etree._Element | None:
    """Root element of a document, or None when the bytes aren't XML (e.g. the site's HTML error page). With a
    `file` name, a document lxml had to repair (it recovers from malformed XML) is logged against that name."""
    errors: list[str] = []
    try:
        root = xmlparse.parse(data, errors)
    except (ValueError, etree.XMLSyntaxError):
        return None
    if errors and file:
        log.warning("mo_house.xml_recovered", file=file, errors=len(errors), first=errors[0])
    return root


def links(root: etree._Element, tag: str) -> list[str]:
    """Texts of every <tag> element anywhere in the tree (RollCallPDF, BillXMLLink, RepresentativeXMLLink)."""
    return [t for _, t in xmlparse.iter_text(root, tag)]


# ---- row types ----------------------------------------------------------------------------------------------
# Every row carries (session_code, file_name), the key of its file in mo_house_xml_files.


@dataclass
class XmlFile:
    """State of one landed file: where it is on disk and what it was."""

    TABLE: ClassVar[str] = "mo_house_xml_files"
    session_code: str
    file_name: str
    kind: str
    item: str
    source_url: str
    path: str  # gzip, relative to MOGOV_RAW_DIR
    size_bytes: int  # XML size before gzip
    gz_bytes: int
    sha256: str  # of the XML bytes
    landed_at: datetime  # when this run wrote the file (not when the House published it)


@dataclass
class Member:
    TABLE: ClassVar[str] = "mo_house_xml_members"
    session_code: str
    file_name: str
    district: str | None
    district_number: int | None
    last_name: str | None
    first_name: str | None
    party: str | None
    year_elected: int | None
    years_served: int | None
    hometown: str | None
    biography: str | None
    photo_link: str | None
    leadership_position: str | None
    vacant_name: str | None


@dataclass
class MemberCommittee:
    TABLE: ClassVar[str] = "mo_house_xml_member_committees"
    session_code: str
    file_name: str
    committee_index: int
    committee_name: str | None
    committee_position: str | None


@dataclass
class MemberCounty:
    TABLE: ClassVar[str] = "mo_house_xml_member_counties"
    session_code: str
    file_name: str
    county_name: str | None


@dataclass
class Bill:
    TABLE: ClassVar[str] = "mo_house_xml_bills"
    session_code: str
    file_name: str
    bill: str  # from the file name, e.g. HB10
    bill_number: str | None
    current_bill_string: str | None
    short_title: str | None
    long_title: str | None
    last_action: str | None
    proposed_effective_date: date | None
    current_lr_number: str | None
    calendar: str | None
    next_house_hearing: str | None
    governor_action: str | None
    governors_veto_letter: str | None
    substituted_by: str | None
    substituted_by_link: str | None
    summary_sheet_link: str | None
    past_session_appropriation_bill: str | None
    # the SenateActList bill element names these (NULL in House bill documents)
    current_version_type_code: str | None
    effective_date_varies: str | None
    sponsor_name: str | None
    sponsor_district: int | None
    sponsor_link: str | None


@dataclass
class BillAction:
    TABLE: ClassVar[str] = "mo_house_xml_bill_actions"
    session_code: str
    file_name: str
    action_index: int  # 1-based position in the document
    description: str | None
    guid: str | None
    activity_sequence: int | None
    pub_date: date | None
    link: str | None
    comments: str | None
    house_journal_start_page: int | None
    house_journal_end_page: int | None
    senate_journal_start_page: int | None
    senate_journal_end_page: int | None
    journal_link: str | None
    rollcall_total_yes: int | None  # printed totals when the action is a recorded vote
    rollcall_total_no: int | None
    rollcall_total_present: int | None


@dataclass
class BillSponsor:
    TABLE: ClassVar[str] = "mo_house_xml_bill_sponsors"
    session_code: str
    file_name: str
    sponsor_index: int
    sponsor_type: str | None
    full_name: str | None
    district: int | None
    cosponsor_entry_date: date | None


@dataclass
class BillText:
    TABLE: ClassVar[str] = "mo_house_xml_bill_texts"
    session_code: str
    file_name: str
    text_index: int
    document_name: str | None
    web_name: str | None
    lr_number: str | None
    version_type_code: str | None
    version_sort: int | None
    text_link: str | None
    summary_text_link: str | None
    map_link: str | None


@dataclass
class BillAmendment:
    TABLE: ClassVar[str] = "mo_house_xml_bill_amendments"
    session_code: str
    file_name: str
    amendment_index: int
    description: str | None
    amendment_text: str | None
    lr_number: str | None
    sort_value: str | None  # e.g. '0507HH': not a number
    sponsor: str | None
    status: str | None
    status_description: str | None
    map_link: str | None


@dataclass
class BillSummary:
    TABLE: ClassVar[str] = "mo_house_xml_bill_summaries"
    session_code: str
    file_name: str
    summary_index: int
    document_name: str | None
    summary_text_link: str | None
    version_type_code: str | None
    lr_number: str | None
    version_sort: int | None


@dataclass
class BillFiscalNote:
    TABLE: ClassVar[str] = "mo_house_xml_bill_fiscal_notes"
    session_code: str
    file_name: str
    fiscal_note_index: int
    element: str  # FiscalNote or FiscalNotes: the XML uses both
    fiscal_note_link: str | None


@dataclass
class BillWitness:
    """A witness-form link on a bill (the forms themselves, which name citizens, are not fetched or parsed)."""

    TABLE: ClassVar[str] = "mo_house_xml_bill_witnesses"
    session_code: str
    file_name: str
    witness_index: int
    witness_forms_link: str | None
    witness_form_link_description: str | None


@dataclass
class BillRollCall:
    """A roll call the XML lists under a bill text version (parent_kind 'text') or an amendment ('amendment')."""

    TABLE: ClassVar[str] = "mo_house_xml_bill_rollcalls"
    session_code: str
    file_name: str
    parent_kind: str
    parent_index: int
    parent_name: str | None  # the text's DocumentName or the amendment's description
    rollcall_index: int
    rollcall_number: int | None
    rollcall_pdf: str | None
    session_day: int | None
    total_yes: int | None
    total_no: int | None
    total_present: int | None


@dataclass
class BillSubject:
    TABLE: ClassVar[str] = "mo_house_xml_bill_subjects"
    session_code: str
    file_name: str
    subject_index: int
    subject_id: str | None
    subject_name: str | None


@dataclass
class BillHearing:
    TABLE: ClassVar[str] = "mo_house_xml_bill_hearings"
    session_code: str
    file_name: str
    hearing_index: int
    committee_name: str | None
    notice_date: date | None
    notice_time: str | None
    alt_time: str | None
    location: str | None
    comments: str | None


@dataclass
class Session:
    TABLE: ClassVar[str] = "mo_house_xml_sessions"
    session_code: str  # of the file: the session whose SessionList this row came from
    file_name: str
    session_id: str | None
    name: str | None
    session_year: int | None
    session_type: str | None
    general_assembly: str | None
    session_of_general_assembly: str | None


@dataclass
class Committee:
    TABLE: ClassVar[str] = "mo_house_xml_committees"
    session_code: str
    file_name: str
    committee_id: str | None
    committee_type: str | None
    name: str | None
    parent_id: str | None
    parent_name: str | None


@dataclass
class CommitteeMember:
    TABLE: ClassVar[str] = "mo_house_xml_committee_members"
    session_code: str
    file_name: str
    committee_id: str | None
    member_index: int
    member_name: str | None
    member_district: int | None
    position_name: str | None
    chamber: str | None


@dataclass
class BillListEntry:
    TABLE: ClassVar[str] = "mo_house_xml_bill_list"
    session_code: str
    file_name: str
    bill_type: str | None
    bill_number: int | None
    session_year: int | None
    session_type: str | None
    xml_link: str | None
    last_time_run: str | None


@dataclass
class MemberListEntry:
    TABLE: ClassVar[str] = "mo_house_xml_member_list"
    session_code: str
    file_name: str
    district: str | None
    xml_link: str | None
    last_time_run: str | None


@dataclass
class UpcomingHearing:
    TABLE: ClassVar[str] = "mo_house_xml_upcoming_hearings"
    session_code: str
    file_name: str
    hearing_id: str | None
    committee_id: str | None
    committee_name: str | None
    hearing_date: str | None
    hearing_time: str | None
    location: str | None
    status: str | None
    progress: str | None
    notice_executive_session: str | None
    comments: str | None
    approved_timestamp: str | None
    chair_first_name: str | None
    chair_last_name: str | None
    chair_district: int | None
    chair_chamber: str | None


@dataclass
class CalendarBill:
    TABLE: ClassVar[str] = "mo_house_xml_calendar_bills"
    session_code: str
    file_name: str
    session_day: str | None
    calendar_name: str | None
    bill_type: str | None
    bill_number: int | None
    current_bill_string: str | None
    short_title: str | None
    sponsor_first_name: str | None
    sponsor_last_name: str | None
    sponsor_district: int | None
    sponsor_chamber: str | None
    handler_first_name: str | None
    handler_last_name: str | None
    handler_district: int | None
    handler_chamber: str | None


@dataclass
class ListNotice:
    """The NOTICE element some list files (CalendarList, UpcomingHearingList) carry next to their items."""

    TABLE: ClassVar[str] = "mo_house_xml_list_notices"
    session_code: str
    file_name: str
    notice: str


BILL_ROW_TYPES: list[type] = [
    Bill,
    BillAction,
    BillSponsor,
    BillText,
    BillAmendment,
    BillRollCall,
    BillSubject,
    BillHearing,
    BillSummary,
    BillFiscalNote,
    BillWitness,
]


def _senate_act_type(row_type: type) -> type:
    """The SenateActList twin of a bill row type: table `mo_house_xml_senate_act_*` and, for child rows, a `bill`
    column naming the Senate bill (many bills share one file)."""
    if row_type is Bill:
        return make_dataclass("SenateActBill", [], bases=(Bill,), namespace={"TABLE": "mo_house_xml_senate_act_bills"})
    table = "mo_house_xml_senate_act_" + row_type.TABLE.removeprefix("mo_house_xml_bill_")
    return make_dataclass(
        "SenateAct" + row_type.__name__.removeprefix("Bill"),
        [("bill", str)],
        bases=(row_type,),
        namespace={"TABLE": table},
    )


# The SenateActList names the sponsor on the bill row (SponsorName/District/Link) and carries no Sponsor or
# SubjectIndex children, so those twin tables would always be empty: not made, and the rows are skipped.
SENATE_ACT_SKIPPED: tuple[type, ...] = (BillSponsor, BillSubject)
SENATE_ACT_TYPES: dict[type, type] = {t: _senate_act_type(t) for t in BILL_ROW_TYPES if t not in SENATE_ACT_SKIPPED}

ROW_TYPES: list[type] = [
    Member,
    MemberCommittee,
    MemberCounty,
    Bill,
    BillAction,
    BillSponsor,
    BillText,
    BillAmendment,
    BillRollCall,
    BillSubject,
    BillHearing,
    Session,
    Committee,
    CommitteeMember,
    BillListEntry,
    MemberListEntry,
    UpcomingHearing,
    CalendarBill,
    ListNotice,
    BillSummary,
    BillFiscalNote,
    BillWitness,
    *SENATE_ACT_TYPES.values(),
]

# ---- document walkers ---------------------------------------------------------------------------------------

Key = tuple[str, str]


def _member(key: Key, root: etree._Element) -> Iterator[object]:
    info = child(child(root, "RepresentativeData"), "RepresentativeInfo")
    if info is None:
        return
    district = text(info, "DistrictNum")
    yield Member(
        *key,
        district,
        int(district) if district and district.isdigit() else None,
        text(info, "LastName"),
        text(info, "FirstName"),
        text(info, "Party"),
        integer(info, "YearElected"),
        integer(info, "YearsServed"),
        text(info, "Hometown"),
        text(info, "Biography"),
        text(info, "PhotoLink"),
        text(info, "LeadershipPosition"),
        text(info, "VacantName"),
    )
    for i, c in enumerate(children(child(info, "Committees"), "Committee"), 1):
        yield MemberCommittee(*key, i, text(c, "CommitteeName"), text(c, "CommitteePosition"))
    for c in children(child(info, "Counties"), "County"):
        yield MemberCounty(*key, text(c, "CountyName"))


def _rollcalls(
    key: Key, parent_kind: str, parent_index: int, parent_name: str | None, holder: etree._Element
) -> Iterator[object]:
    for i, r in enumerate(children(child(holder, "RollCalls"), "RollCall"), 1):
        yield BillRollCall(
            *key,
            parent_kind,
            parent_index,
            parent_name,
            i,
            integer(r, "RollCallNumber"),
            text(r, "RollCallPDF"),
            integer(r, "SessionDay"),
            integer(r, "TotalYes"),
            integer(r, "TotalNo"),
            integer(r, "TotalPresent"),
        )


def _bill(key: Key, bill: str, info: etree._Element) -> Iterator[object]:
    """Rows of one <BillInformation> element: a bill document's, or one item of a SenateActList (which differs
    only in a few places: titles sit directly in the element, the governor's action is nested once more, and
    the sponsor is named in SponsorName/District/Link instead of Sponsor children)."""
    title = child(info, "Title")
    if title is None:
        title = info
    gov = child(info, "GovernorLastAction")
    if (inner := child(gov, "GovernorLastAction")) is not None:
        gov = inner
    yield Bill(
        *key,
        bill,
        text(info, "BillNumber"),
        text(info, "CurrentBillString"),
        text(title, "ShortTitle"),
        text(title, "LongTitle"),
        text(info, "LastAction"),
        day(info, "ProposedEffectiveDate"),
        text(info, "CurrentLRNumber"),
        text(info, "Calendar"),
        text(info, "NextHouseHearing"),
        text(gov, "GovernorAction"),
        text(gov, "GovernorsVetoLetter"),
        text(child(info, "SubstitutedBy"), "ParentBillString"),
        text(child(info, "SubstitutedBy"), "ParentBillLink"),
        text(child(info, "SummarySheet"), "SummarySheetLink"),
        text(info, "PastSessionAppropriationBill"),
        text(info, "CurrentVersionTypeCode"),
        text(info, "EffectiveDateVaries"),
        text(info, "SponsorName"),
        integer(info, "SponsorDistrict"),
        text(info, "SponsorLink"),
    )
    for i, a in enumerate(children(info, "Action"), 1):
        rc = child(a, "RollCall")
        yield BillAction(
            *key,
            i,
            text(a, "Description"),
            text(a, "Guid"),
            integer(a, "ActivitySequence"),
            day(a, "PubDate"),
            text(a, "Link"),
            text(a, "Comments"),
            integer(a, "HouseJournalStartPage"),
            integer(a, "HouseJournalEndPage"),
            integer(a, "SenateJournalStartPage"),
            integer(a, "SenateJournalEndPage"),
            text(a, "JournalLink"),
            integer(rc, "TotalYes"),
            integer(rc, "TotalNo"),
            integer(rc, "TotalPresent"),
        )
    for i, s in enumerate(children(info, "Sponsor"), 1):
        yield BillSponsor(
            *key, i, text(s, "SponsorType"), text(s, "FullName"), integer(s, "District"), day(s, "CoSponsorEntryDate")
        )
    for i, t in enumerate(children(info, "BillText"), 1):
        name = text(t, "DocumentName")
        yield BillText(
            *key,
            i,
            name,
            text(t, "WebName"),
            text(t, "LRNumber"),
            text(t, "VersionTypeCode"),
            integer(t, "BillVersionSort"),
            text(t, "BillTextLink"),
            text(t, "SummaryTextLink"),
            text(child(t, "Map"), "MapLink"),
        )
        yield from _rollcalls(key, "text", i, name, t)
    for i, am in enumerate(children(info, "Amendment"), 1):
        desc = text(am, "AmendmentDescription")
        yield BillAmendment(
            *key,
            i,
            desc,
            text(am, "AmendmentText"),
            text(am, "LRNumber"),
            text(am, "AmendmentSortValue"),
            text(am, "Sponsor"),
            text(am, "Status"),
            text(am, "StatusDescription"),
            text(child(am, "Map"), "MapLink"),
        )
        yield from _rollcalls(key, "amendment", i, desc, am)
    for i, s in enumerate(children(info, "SubjectIndex"), 1):
        yield BillSubject(*key, i, text(s, "SubjectID"), text(s, "SubjectName"))
    for i, h in enumerate(children(info, "Hearings"), 1):
        yield BillHearing(
            *key,
            i,
            text(h, "CommitteeName"),
            day(h, "NoticeDate"),
            text(h, "NoticeTime"),
            text(h, "AltTime"),
            text(h, "Location"),
            text(h, "Comments"),
        )
    for i, s in enumerate(children(info, "BillSummary"), 1):
        yield BillSummary(
            *key,
            i,
            text(s, "DocumentName"),
            text(s, "SummaryTextLink"),
            text(s, "VersionTypeCode"),
            text(s, "LRNumber"),
            integer(s, "BillVersionSort"),
        )
    fiscal_notes = [
        (_local(note), link)
        for note in info
        if _local(note) in ("FiscalNote", "FiscalNotes")
        for link in children(note, "FiscalNoteLink")
    ]
    for i, (element, link) in enumerate(fiscal_notes, 1):
        yield BillFiscalNote(*key, i, element or "FiscalNote", "".join(link.itertext()).strip() or None)
    for i, w in enumerate(children(info, "Witness"), 1):
        link, description = text(w, "WitnessFormsLink"), text(w, "WitnessFormLinkDescription")
        if link is None and description is None:
            continue  # an empty <Witness/>: nothing to keep (witness_index still counts it)
        yield BillWitness(*key, i, link, description)


def _bill_document(key: Key, bill: str, root: etree._Element) -> Iterator[object]:
    if (info := child(root, "BillInformation")) is not None:
        yield from _bill(key, bill, info)


def _senate_act_list(key: Key, root: etree._Element) -> Iterator[object]:
    """The House's actions on Senate bills: each item is a bill element. Rows go to the `senate_act` twin of the
    bill tables and (children) carry the bill they belong to."""
    for holder in children(root, "SenateBillsWithHouseActions"):
        for info in children(holder, "BillInformation"):
            bill = text(info, "BillNumber") or ""
            for row in _bill(key, bill, info):
                if isinstance(row, SENATE_ACT_SKIPPED):
                    continue
                twin = SENATE_ACT_TYPES[type(row)]
                values = {f.name: getattr(row, f.name) for f in fields(row)}
                yield twin(**values) if isinstance(row, Bill) else twin(**values, bill=bill)


def _sessions(key: Key, root: etree._Element) -> Iterator[object]:
    for s in children(root, "Session"):
        yield Session(
            *key,
            text(s, "ID"),
            text(s, "Name"),
            integer(s, "SessionYear"),
            text(s, "SessionCode"),
            text(s, "GeneralAssembly"),
            text(s, "SessionOfGeneralAssembly"),
        )


def _committees(key: Key, root: etree._Element) -> Iterator[object]:
    for c in children(root, "Committee"):
        cid = text(c, "ID")
        yield Committee(*key, cid, text(c, "Type"), text(c, "Name"), text(c, "ParentID"), text(c, "ParentName"))
        for i, m in enumerate(children(child(c, "CommitteeMembers"), "CommitteeMember"), 1):
            yield CommitteeMember(
                *key,
                cid,
                i,
                text(m, "MemberName"),
                integer(m, "MemberDistrict"),
                text(m, "PositionName"),
                text(m, "Chamber"),
            )


def _bill_list(key: Key, root: etree._Element) -> Iterator[object]:
    for b in children(root, "BillXML"):
        yield BillListEntry(
            *key,
            text(b, "BillType"),
            integer(b, "BillNumber"),
            integer(b, "SessionYear"),
            text(b, "SessionCode"),
            text(b, "BillXMLLink"),
            text(b, "LastTimeRun"),
        )


def _member_list(key: Key, root: etree._Element) -> Iterator[object]:
    for m in children(root, "RepresentativeXML"):
        yield MemberListEntry(
            *key, text(m, "RepresentativeDistrict"), text(m, "RepresentativeXMLLink"), text(m, "LastTimeRun")
        )


def _hearings(key: Key, root: etree._Element) -> Iterator[object]:
    for h in children(root, "HearingInfo"):
        yield UpcomingHearing(
            *key,
            text(h, "HearingID"),
            text(h, "CommitteeID"),
            text(h, "CommitteeName"),
            text(h, "HearingDate"),
            text(h, "HearingTime"),
            text(h, "HearingLocation"),
            text(h, "HearingStatus"),
            text(h, "HearingProgress"),
            text(h, "NoticeExecutiveSession"),
            text(h, "Comments"),
            text(h, "ApprovedTimeStamp"),
            text(h, "CommitteeChairFirstName"),
            text(h, "CommitteeChairLastName"),
            integer(h, "CommitteeChairDistrict"),
            text(h, "CommitteeChairChamber"),
        )


def _calendar(key: Key, root: etree._Element) -> Iterator[object]:
    for d in children(root, "DailyCalendar"):
        session_day = text(child(d, "SessionDay"), "DateString")
        for cal in children(d, "Calendar"):
            for b in children(cal, "BillInfo"):
                yield CalendarBill(
                    *key,
                    session_day,
                    text(cal, "CalendarName"),
                    text(b, "BillType"),
                    integer(b, "BillNumber"),
                    text(b, "CurrentBillString"),
                    text(b, "ShortTitle"),
                    text(b, "SponsorFirstName"),
                    text(b, "SponsorLastName"),
                    integer(b, "SponsorDistrict"),
                    text(b, "SponsorChamber"),
                    text(b, "HandlerFirstName"),
                    text(b, "HandlerLastName"),
                    integer(b, "HandlerDistrict"),
                    text(b, "HandlerChamber"),
                )


LIST_WALKERS: dict[str, Callable[[Key, etree._Element], Iterator[object]]] = {
    "SESSIONLIST": _sessions,
    "COMMITTEELIST": _committees,
    "BILLLIST": _bill_list,
    "MEMBERLIST": _member_list,
    "UPCOMINGHEARINGLIST": _hearings,
    "CALENDARLIST": _calendar,
    "SENATEACTLIST": _senate_act_list,
}


def parse_document(session_code: str, file_name: str, root: etree._Element) -> Iterator[object]:
    """Typed rows of one document; nothing for files that are landed but not parsed (kind 'other')."""
    kind, item = classify(file_name)
    key = (session_code, file_name)
    if kind == KIND_MEMBER:
        yield from _member(key, root)
    elif kind == KIND_BILL:
        yield from _bill_document(key, item, root)
    elif kind == KIND_LIST:
        if walker := LIST_WALKERS.get(item):
            yield from walker(key, root)
        if notice := text(root, "NOTICE"):
            yield ListNotice(*key, notice)


# ---- from landed files to raw tables ------------------------------------------------------------------------


def read_landed(path: str) -> bytes:
    """The XML bytes of a landed file (`path` as stored in mo_house_xml_files, relative to the raw dir)."""
    with gzip.open(db.RAW_DIR / path, "rb") as fh:
        return fh.read()


def landed_files(shard: db.Shard) -> list[tuple[str, str, str]]:
    """(session_code, file_name, path) of this shard's landed files, from the state table."""
    if not db.raw_exists(XmlFile.TABLE):
        return []
    with db.connect() as con:
        own = db.own_rows_sql(XmlFile.TABLE, ["session_code", "file_name"])
        rows = con.execute(
            f"select session_code, file_name, path from ({own}) order by session_code, file_name"
        ).fetchall()
    return [r for r in rows if shard.owns(r[0])]


def parse_landed(shard: db.Shard) -> dict[str, int]:
    """Parse every landed file this shard owns into the typed raw tables (replacing this shard's parts).
    Streams: one document in memory at a time."""
    files = landed_files(shard)
    progress = obs.Progress("xml files", len(files), log)
    with db.TableSink(shard, tables=ROW_TYPES) as sink:
        for session_code, file_name, path in files:
            progress.tick()
            root = parse_xml(read_landed(path), file_name)
            if root is None:
                log.warning("mo_house.xml_unparseable", file=file_name, session=session_code)
                continue
            for row in parse_document(session_code, file_name, root):
                sink.add(row)
        progress.finish()
    return sink.counts


def main() -> None:
    """Re-parse the landed files without fetching anything: python -m mogov.parsers.mo_house [--shards N --shard I]"""
    import argparse

    ap = argparse.ArgumentParser(description=main.__doc__)
    ap.add_argument("--shards", type=int, default=1)
    ap.add_argument("--shard", type=int, default=0)
    args = ap.parse_args()
    for table, n in parse_landed(db.Shard(args.shard, args.shards)).items():
        log.info("parser.landed", table=f"raw.{table}", rows=n)


if __name__ == "__main__":
    main()
