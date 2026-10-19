"""Write dbt/models/{staging,intermediate}/_<layer>.yml model descriptions from each model's header comment,
plus a hand-written grain line. Run from the repo root:

    uv run python scripts/gen_model_docs.py

Re-run after adding a model or editing a header. Mart docs are hand-written in models/marts/_marts.yml;
unit tests live in their own files so regenerating never touches them."""

from pathlib import Path

import yaml

GRAIN = {
    "int_bills__subjects": "one row per (session, bill, subject) from one chamber's index",
    "int_bluebook__bios": "one biography per (edition, person) in the legislative/executive chapters",
    "int_bluebook__judge_bios": "one biography per judge in the judicial chapter",
    "int_bluebook__county_circuits": "one row per county (and St. Louis City) in the latest edition",
    "int_courtlistener__bulk_case_matches": "one row per (official, role, cluster); matched_by says how",
    "int_courtlistener__judge_disclosure_items": "one disclosed item per federal judge report",
    "int_courtlistener__mo_cases": "one row per opinion cluster (decided case) in a tracked court",
    "int_courtlistener__official_people": "one row per (official, CourtListener person)",
    "int_courtlistener__official_positions": "one row per CourtListener position of a matched official",
    "int_house_fd__schedule_lines": "one text line per House disclosure PDF, tagged with its schedule",
    "int_interests__industry_money": "one row per (official, industry, money kind, year)",
    "int_judges__current": "one row per sitting judge (state and federal)",
    "int_judges__federal": "one row per sitting federal judge in Missouri",
    "int_judges__state_index": "one row per state judge in the Official Manual index",
    "int_mec__official_committees": "one row per (official, MEC committee) with a confidence label",
    "int_mo_house__member_identity": "one row per (House session, member) with a person_key",
    "int_mo_house__votes": "one row per (House roll call, attributed person)",
    "int_mo_legislators__seats": "one row per Open States legislative seat-term",
    "int_mo_senate__votes": "one row per (Senate journal vote, attributed person)",
    "int_officials__bios": "one biography text per official per source",
    "int_officials__current": "one row per (person, current office)",
    "int_officials__name_keys": "one row per (official, normalized name variant)",
    "int_officials__wikidata": "one row per official with a Wikidata QID",
    "int_votes__member_votes": "one row per (chamber, vote, member) for every member, tracked or not",
    "int_votes__party_positions": "one row per (chamber, vote) with any Republican or Democratic yea/nay",
}


def header(path: Path) -> str:
    lines = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("{{ config"):
            continue
        if not line.startswith("--"):
            break
        lines.append(line[2:].strip())
    return " ".join(lines)


def write(folder: Path, out: Path) -> None:
    models = []
    for path in sorted(folder.glob("*.sql")):
        text = header(path)
        if path.stem in GRAIN:
            text += f" Grain: {GRAIN[path.stem]}."
        models.append({"name": path.stem, "description": text.strip()})
    body = yaml.safe_dump({"version": 2, "models": models}, sort_keys=False, width=110, allow_unicode=True)
    out.write_text(
        f"# Generated from each model's header comment (+ grain for intermediate models); edit the SQL header,\n"
        f"# not this file, then regenerate.\n{body}",
        encoding="utf-8",
        newline="\n",
    )
    print(out, len(models))


# staging: one folder per source system, docs beside its _<system>__sources.yml
for system in sorted(p for p in Path("dbt/models/staging").iterdir() if p.is_dir()):
    write(system, system / f"_{system.name}__models.yml")
write(Path("dbt/models/intermediate"), Path("dbt/models/intermediate/_intermediate.yml"))
