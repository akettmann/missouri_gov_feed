"""Parser for the GovInfo BILLSTATUS bulk XML files landed by `mogov.loaders.govinfo_billstatus`.

One file is one federal bill (`<billStatus><bill>...`). It is walked with lxml (hardened settings, via
`mogov.xmlparse`) and emits one row per entity it contains, keyed so a re-parse gives the same keys:

- bill            -> `govinfo_billstatus_bills` (number, type, dates, title, policy area, latest action)
- sponsors        -> `govinfo_billstatus_sponsors`    (one per sponsor; `bioguideId` joins congress_legislators)
- cosponsors      -> `govinfo_billstatus_cosponsors`  (with sponsorship date and original / withdrawn flags)
- actions         -> `govinfo_billstatus_actions`
- recorded votes  -> `govinfo_billstatus_recorded_votes` (the roll calls an action cites: chamber, session, roll number)
- laws            -> `govinfo_billstatus_laws`        (the Public Law number a bill became)

Elements are selected by local name. Empty elements are None, text is only stripped, and nothing is interpreted:
what became law, and which outcomes count as success, is dbt's call. Committees, subjects, summaries, titles and
text versions stay in the raw XML (see docs/sources.md).
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
    congress, bill_type, number = text(bill, "congress"), text(bill, "type"), text(bill, "number")
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
    return out


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
