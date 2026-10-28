"""Parser for the GovInfo BILLSTATUS bulk XML files landed by `mogov.loaders.govinfo_billstatus`.

One file is one federal bill (`<billStatus><bill>...`). It is walked with lxml (hardened settings, via
`mogov.xmlparse`) and emits one row per entity it contains, keyed so a re-parse gives the same keys:

- bill            -> `govinfo_billstatus_bills` (number, type, dates, title, policy area, latest action)
- sponsors        -> `govinfo_billstatus_sponsors`    (one per sponsor; `bioguideId` joins congress_legislators)
- cosponsors      -> `govinfo_billstatus_cosponsors`  (with sponsorship date and original / withdrawn flags)
- actions         -> `govinfo_billstatus_actions`
- recorded votes  -> `govinfo_billstatus_recorded_votes` (the roll calls an action cites: chamber, session, roll number)
- laws            -> `govinfo_billstatus_laws`        (the Public Law number a bill became)
- committees      -> `govinfo_billstatus_committees` (referral committees and their subcommittees, one row each) and
                     `govinfo_billstatus_committee_activities` (one row per dated activity: Referred to, Markup by, ...)
- subjects        -> `govinfo_billstatus_subjects`    (CRS legislative subject terms; the policy area is a bills column)
- related bills   -> `govinfo_billstatus_related_bills` (identified-by-CRS/House related bills) and
                     `govinfo_billstatus_related_bill_relationships` (one row per relationship type of a related bill)
- amendments      -> `govinfo_billstatus_amendments` (the amendments filed to the bill: number, type, chamber,
                     purpose, dates, the bill amended), `govinfo_billstatus_amendment_sponsors` (sponsors, and
                     the senators an amendment was proposed on behalf of),
                     `govinfo_billstatus_amendment_actions` and
                     `govinfo_billstatus_amendment_recorded_votes` (the roll calls those actions cite)

Elements are selected by local name. Empty elements are None, text is only stripped, and nothing is interpreted:
what became law, and which outcomes count as success, is dbt's call. Summaries, titles, text versions and
amendment cosponsors, text versions and links stay in the raw XML (see docs/sources.md).

The 11 reserved 117th House bills use an older export that wraps the lists one level deeper
(`committees/billCommittees/item`, `subjects/billSubjects/legislativeSubjects`); both layouts are read.
"""

from lxml import etree

from mogov import xmlparse

TABLES = {
    "bills": "govinfo_billstatus_bills",
    "sponsors": "govinfo_billstatus_sponsors",
    "cosponsors": "govinfo_billstatus_cosponsors",
    "actions": "govinfo_billstatus_actions",
    "recorded_votes": "govinfo_billstatus_recorded_votes",
    "laws": "govinfo_billstatus_laws",
    "committees": "govinfo_billstatus_committees",
    "committee_activities": "govinfo_billstatus_committee_activities",
    "subjects": "govinfo_billstatus_subjects",
    "related_bills": "govinfo_billstatus_related_bills",
    "related_bill_relationships": "govinfo_billstatus_related_bill_relationships",
    "amendments": "govinfo_billstatus_amendments",
    "amendment_sponsors": "govinfo_billstatus_amendment_sponsors",
    "amendment_actions": "govinfo_billstatus_amendment_actions",
    "amendment_recorded_votes": "govinfo_billstatus_amendment_recorded_votes",
}
ALL_TABLES = list(TABLES.values())

Row = tuple[str, dict]  # (record_key, payload)


def _local(el: etree._Element) -> str | None:
    return etree.QName(el).localname if isinstance(el.tag, str) else None


def child(el: etree._Element | None, name: str) -> etree._Element | None:
    return next((c for c in el if _local(c) == name), None) if el is not None else None


def items(el: etree._Element | None, name: str) -> list[etree._Element]:
    """The <item> children of the first <name> child (BILLSTATUS lists are `<name><item>...</item></name>`)."""
    return [c for c in child(el, name) if _local(c) == "item"] if child(el, name) is not None else []


def text(el: etree._Element | None, name: str) -> str | None:
    c = child(el, name)
    return ("".join(c.itertext()).strip() or None) if c is not None else None


def bill_id(congress: str | None, bill_type: str | None, number: str | None) -> str:
    return f"{congress}-{(bill_type or '').lower()}-{number}"


def parse_bill(xml: bytes, file_name: str, errors: list[str] | None = None) -> dict[str, list[Row]]:
    """{table key from TABLES: [(record_key, payload), ...]} for one BILLSTATUS file. Raises ValueError when the
    bytes have no <bill> (the file is not a BILLSTATUS document)."""
    root = xmlparse.parse(xml, errors)
    bill = child(root, "bill")
    if bill is None:
        raise ValueError(f"{file_name}: no <bill> element")
    # The 11 reserved 117th House bills (hr2, hr9-17, hr20) are an older export that names these `billType` and
    # `billNumber`; every other file uses `type` and `number`.
    congress = text(bill, "congress")
    bill_type = text(bill, "type") or text(bill, "billType")
    number = text(bill, "number") or text(bill, "billNumber")
    bid = bill_id(congress, bill_type, number)
    out: dict[str, list[Row]] = {name: [] for name in TABLES}
    latest = child(bill, "latestAction")
    out["bills"].append(
        (
            bid,
            {
                "bill_id": bid,
                "file_name": file_name,
                "congress": congress,
                "bill_type": bill_type,
                "number": number,
                "origin_chamber": text(bill, "originChamber"),
                "introduced_date": text(bill, "introducedDate"),
                "update_date": text(bill, "updateDate"),
                "title": text(bill, "title"),
                "policy_area": text(child(bill, "policyArea"), "name"),
                "legislation_url": text(bill, "legislationUrl"),
                "latest_action_date": text(latest, "actionDate"),
                "latest_action_text": text(latest, "text"),
            },
        )
    )
    for i, s in enumerate(items(bill, "sponsors")):
        out["sponsors"].append((f"{bid}#{i}", {"bill_id": bid, "position": i, **_person(s)}))
    for i, s in enumerate(items(bill, "cosponsors")):
        out["cosponsors"].append(
            (
                f"{bid}#{i}",
                {
                    "bill_id": bid,
                    "position": i,
                    **_person(s),
                    "sponsorship_date": text(s, "sponsorshipDate"),
                    "is_original_cosponsor": text(s, "isOriginalCosponsor"),
                    "sponsorship_withdrawn_date": text(s, "sponsorshipWithdrawnDate"),
                },
            )
        )
    for i, a in enumerate(items(bill, "actions")):
        out["actions"].append(
            (
                f"{bid}#{i}",
                {
                    "bill_id": bid,
                    "position": i,
                    "action_date": text(a, "actionDate"),
                    "action_time": text(a, "actionTime"),
                    "text": text(a, "text"),
                    "action_type": text(a, "type"),
                    "action_code": text(a, "actionCode"),
                    "source_system": text(child(a, "sourceSystem"), "name"),
                },
            )
        )
        votes = child(a, "recordedVotes")
        for j, v in enumerate(c for c in (votes if votes is not None else []) if _local(c) == "recordedVote"):
            out["recorded_votes"].append(
                (
                    f"{bid}#{i}#{j}",
                    {
                        "bill_id": bid,
                        "action_position": i,
                        "chamber": text(v, "chamber"),
                        "congress": text(v, "congress"),
                        "session_number": text(v, "sessionNumber"),
                        "roll_number": text(v, "rollNumber"),
                        "vote_date": text(v, "date"),
                        "url": text(v, "url"),
                    },
                )
            )
    for i, law in enumerate(items(bill, "laws")):
        out["laws"].append(
            (
                f"{bid}#{i}",
                {"bill_id": bid, "position": i, "law_type": text(law, "type"), "law_number": text(law, "number")},
            )
        )
    _committees(out, bid, bill)
    for i, subj in enumerate(items(_unwrap(child(bill, "subjects"), "billSubjects"), "legislativeSubjects")):
        out["subjects"].append(
            (
                f"{bid}#{i}",
                {"bill_id": bid, "position": i, "name": text(subj, "name"), "update_date": text(subj, "updateDate")},
            )
        )
    for i, rel in enumerate(items(bill, "relatedBills")):
        rel_type = text(rel, "type")
        out["related_bills"].append(
            (
                f"{bid}#{i}",
                {
                    "bill_id": bid,
                    "position": i,
                    "related_congress": text(rel, "congress"),
                    "related_bill_type": rel_type,
                    "related_number": text(rel, "number"),
                    "title": text(rel, "title"),
                    "latest_action_date": text(child(rel, "latestAction"), "actionDate"),
                    "latest_action_text": text(child(rel, "latestAction"), "text"),
                },
            )
        )
        for j, detail in enumerate(items(rel, "relationshipDetails")):
            out["related_bill_relationships"].append(
                (
                    f"{bid}#{i}#{j}",
                    {
                        "bill_id": bid,
                        "related_position": i,
                        "position": j,
                        "relationship_type": text(detail, "type"),
                        "identified_by": text(detail, "identifiedBy"),
                    },
                )
            )
    _amendments(out, bid, bill)
    return out


def _recorded_votes(action: etree._Element) -> list[etree._Element]:
    votes = child(action, "recordedVotes")
    return [c for c in (votes if votes is not None else []) if _local(c) == "recordedVote"]


def _amendments(out: dict[str, list[Row]], bid: str, bill: etree._Element) -> None:
    """The amendments filed to the bill (`<amendments><amendment>`), each with its sponsors and its own actions and
    recorded votes. Keyed by the amendment id ("118-hamdt-180"); `bill_id` is the file's bill, and the amended bill
    named inside the amendment is kept beside it (`amended_bill_id`) so dbt can check they agree. The files of the
    reserved older export have no amendments list."""
    container = _unwrap(child(bill, "amendments"), "billAmendments")
    for a in (c for c in (container if container is not None else []) if _local(c) in ("amendment", "item")):
        a_type = text(a, "type")
        aid = bill_id(text(a, "congress"), a_type, text(a, "number"))
        ab = child(a, "amendedBill")
        aa = child(a, "amendedAmendment")
        latest = child(a, "latestAction")
        out["amendments"].append(
            (
                aid,
                {
                    "amendment_id": aid,
                    "bill_id": bid,
                    "congress": text(a, "congress"),
                    "amendment_type": a_type,
                    "number": text(a, "number"),
                    "chamber": text(a, "chamber"),
                    "description": text(a, "description"),
                    "purpose": text(a, "purpose"),
                    "submitted_date": text(a, "submittedDate"),
                    "proposed_date": text(a, "proposedDate"),
                    "update_date": text(a, "updateDate"),
                    "latest_action_date": text(latest, "actionDate"),
                    "latest_action_text": text(latest, "text"),
                    "amended_bill_congress": text(ab, "congress"),
                    "amended_bill_type": text(ab, "type"),
                    "amended_bill_number": text(ab, "number"),
                    "amended_amendment_congress": text(aa, "congress"),
                    "amended_amendment_type": text(aa, "type"),
                    "amended_amendment_number": text(aa, "number"),
                    "amendments_to_amendment_count": text(child(a, "amendmentsToAmendment"), "count"),
                },
            )
        )
        sponsors = [("sponsor", s) for s in items(a, "sponsors")]
        sponsors += [("on_behalf_of", s) for s in items(a, "onBehalfOfSponsor")]
        for i, (role, s) in enumerate(sponsors):
            # a committee sponsors some House amendments (`<name>Rules Committee</name>`, no bioguideId)
            out["amendment_sponsors"].append(
                (
                    f"{aid}#{i}",
                    {
                        "amendment_id": aid,
                        "bill_id": bid,
                        "position": i,
                        "role": role,
                        "name": text(s, "name"),
                        **_person(s),
                    },
                )
            )
        # amendment actions are nested one level deeper than a bill's: <actions><count/><actions><item/>
        for i, act in enumerate(items(child(a, "actions"), "actions")):
            out["amendment_actions"].append(
                (
                    f"{aid}#{i}",
                    {
                        "amendment_id": aid,
                        "bill_id": bid,
                        "position": i,
                        "action_date": text(act, "actionDate"),
                        "action_time": text(act, "actionTime"),
                        "text": text(act, "text"),
                        "action_type": text(act, "type"),
                        "action_code": text(act, "actionCode"),
                        "source_system": text(child(act, "sourceSystem"), "name"),
                    },
                )
            )
            for j, v in enumerate(_recorded_votes(act)):
                out["amendment_recorded_votes"].append(
                    (
                        f"{aid}#{i}#{j}",
                        {
                            "amendment_id": aid,
                            "bill_id": bid,
                            "action_position": i,
                            "chamber": text(v, "chamber"),
                            "congress": text(v, "congress"),
                            "session_number": text(v, "sessionNumber"),
                            "roll_number": text(v, "rollNumber"),
                            "vote_date": text(v, "date"),
                            "url": text(v, "url"),
                        },
                    )
                )


def _unwrap(el: etree._Element | None, old_wrapper: str) -> etree._Element | None:
    """`el`, or its `<old_wrapper>` child when the older export put the list one level deeper."""
    inner = child(el, old_wrapper)
    return inner if inner is not None else el


def _committees(out: dict[str, list[Row]], bid: str, bill: etree._Element) -> None:
    """Committees the bill was referred to, each with its subcommittees (rows with `parent_system_code` set) and
    their dated activities. `position` counts committees; `subposition` counts a committee's subcommittees."""
    container = _unwrap(child(bill, "committees"), "billCommittees")
    for i, c in enumerate(c for c in (container if container is not None else []) if _local(c) == "item"):
        sys_code = text(c, "systemCode")
        out["committees"].append(
            (
                f"{bid}#{i}",
                {
                    "bill_id": bid,
                    "position": i,
                    "subposition": None,
                    "system_code": sys_code,
                    "parent_system_code": None,
                    "name": text(c, "name"),
                    "chamber": text(c, "chamber"),
                    "committee_type": text(c, "type"),
                },
            )
        )
        _activities(out, bid, f"{bid}#{i}", i, None, sys_code, c)
        for j, sub in enumerate(items(c, "subcommittees")):
            out["committees"].append(
                (
                    f"{bid}#{i}#s{j}",
                    {
                        "bill_id": bid,
                        "position": i,
                        "subposition": j,
                        "system_code": text(sub, "systemCode"),
                        "parent_system_code": sys_code,
                        "name": text(sub, "name"),
                        "chamber": None,  # the file leaves it out; dbt takes the parent committee's
                        "committee_type": None,
                    },
                )
            )
            _activities(out, bid, f"{bid}#{i}#s{j}", i, j, text(sub, "systemCode"), sub)


def _activities(
    out: dict[str, list[Row]], bid: str, key: str, position: int, subposition: int | None, sys_code: str | None, el
) -> None:
    for k, a in enumerate(items(el, "activities")):
        out["committee_activities"].append(
            (
                f"{key}#a{k}",
                {
                    "bill_id": bid,
                    "position": position,
                    "subposition": subposition,
                    "activity_position": k,
                    "system_code": sys_code,
                    "activity": text(a, "name"),
                    "activity_date": text(a, "date"),
                },
            )
        )


def _person(el: etree._Element) -> dict:
    return {
        "bioguide_id": text(el, "bioguideId"),
        "full_name": text(el, "fullName"),
        "first_name": text(el, "firstName"),
        "middle_name": text(el, "middleName"),
        "last_name": text(el, "lastName"),
        "party": text(el, "party"),
        "state": text(el, "state"),
        "district": text(el, "district"),
        "is_by_request": text(el, "isByRequest"),
    }
