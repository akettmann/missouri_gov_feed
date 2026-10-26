"""Write dbt/models/{staging,intermediate}/_<layer>.yml model descriptions from each model's header comment,
plus a hand-written grain line. Run from the repo root:

    uv run python scripts/gen_model_docs.py          # rewrite the yml
    uv run python scripts/gen_model_docs.py --check  # write nothing; exit 1 if any yml is stale (pre-commit/CI)

Re-run after adding a model or editing a header. Mart docs are hand-written in models/marts/_marts.yml;
unit tests live in their own files so regenerating never touches them."""

import sys
from pathlib import Path

import yaml

GRAIN = {
    "int_bills__list": "one row per (session, bill), House and Senate bills",
    "int_bills__status": "one row per (session, bill) in the House XML export, House and Senate bills",
    "int_bills__subjects": "one row per (session, bill, subject) from one chamber's index",
    "int_bluebook__bios": "one biography per (edition, person) in the legislative/executive chapters",
    "int_bluebook__judge_bios": "one biography per judge in the judicial chapter",
    "int_bluebook__county_circuits": "one row per county (and St. Louis City) in the latest edition",
    "int_courtlistener__bulk_case_matches": "one row per (official, role, cluster); matched_by says how",
    "int_courtlistener__district_dockets": "one row per federal district docket with an assigned judge",
    "int_courtlistener__judge_disclosure_items": "one disclosed item per federal judge report",
    "int_courtlistener__mo_cases": "one row per opinion cluster (decided case) in a tracked court",
    "int_courtlistener__official_people": "one row per (official, CourtListener person)",
    "int_courtlistener__official_positions": "one row per CourtListener position of a matched official",
    "int_epa_frs__facilities": "one row per geocoded EPA FRS facility",
    "int_house_fd__schedule_lines": "one text line per House disclosure PDF, tagged with its schedule",
    "int_interests__industry_money": "one row per (official, industry, money kind, year)",
    "int_judges__current": "one row per sitting judge (state and federal)",
    "int_judges__federal": "one row per sitting federal judge in Missouri",
    "int_judges__state_index": "one row per state judge in the Official Manual index",
    "int_mec__committee_names": "one row per (MEC committee, name it filed under)",
    "int_mec__contributions_received": "one itemized contribution received by a Missouri committee",
    "int_mec__donor_committees": "one row per (donor committee name as reported, contribution year)",
    "int_mec__official_committees": "one row per (official, MEC committee) with a confidence label",
    "int_mo_house__committee_memberships": "one row per (House session, member, committee)",
    "int_mo_house__member_identity": "one row per (House session, member) with a person_key",
    "int_mo_house__member_seat_keys": "one row per (House session, member) with the seat-matched raw_person_key",
    "int_mo_auditor__reports": "one row per State Auditor report, with its rating and audited entity type",
    "int_mo_house__votes": "one row per (House roll call, attributed person)",
    "int_mo_legislators__seats": "one row per Open States legislative seat-term",
    "int_mo_revisor__session_law_bills": "one row per (RSMo section version, act, bill) a history or repeal note names",
    "int_mo_legislators__seat_terms": "one row per Open States legislative seat-term, under the id Open States gave",
    "int_mo_senate__votes": "one row per (Senate journal vote, attributed person)",
    "int_officeholders__years": "one row per (year, person, office) for offices with dated past rosters",
    "int_officials__bios": "one biography text per official per source",
    "int_officials__current": "one row per (person, current office)",
    "int_officials__identity_terms": "one row per (id as sourced, year, office, district)",
    "int_officials__name_keys": "one row per (official, normalized name variant)",
    "int_officials__person_ids": "one row per id a legislator has been given, with the stable person_id",
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


def render(folder: Path, out: Path) -> str:
    # hand-written keys (columns with tests, data_tests...) survive regeneration; only descriptions are rewritten
    kept = {}
    if out.exists():
        kept = {m["name"]: m for m in (yaml.safe_load(out.read_text(encoding="utf-8")) or {}).get("models", [])}
    models = []
    for path in sorted(folder.glob("*.sql")):
        text = header(path)
        if path.stem in GRAIN:
            text += f" Grain: {GRAIN[path.stem]}."
        extra = {k: v for k, v in kept.get(path.stem, {}).items() if k not in ("name", "description")}
        models.append({"name": path.stem, "description": text.strip(), **extra})
    body = yaml.safe_dump({"version": 2, "models": models}, sort_keys=False, width=110, allow_unicode=True)
    return (
        f"# Generated from each model's header comment (+ grain for intermediate models); edit the SQL header,\n"
        f"# not this file, then regenerate.\n{body}"
    )


def targets(models: Path) -> list[tuple[Path, Path]]:
    # staging: one folder per source system, docs beside its _<system>__sources.yml
    systems = sorted(p for p in (models / "staging").iterdir() if p.is_dir())
    pairs = [(d, d / f"_{d.name}__models.yml") for d in systems]
    return [*pairs, (models / "intermediate", models / "intermediate" / "_intermediate.yml")]


def main(argv: list[str], models: Path = Path("dbt/models")) -> int:
    check = "--check" in argv
    stale = []
    for folder, out in targets(models):
        text = render(folder, out)
        if check:
            # read_text uses universal newlines, so a CRLF checkout does not read as stale
            if not out.exists() or out.read_text(encoding="utf-8") != text:
                stale.append(out)
            continue
        out.write_text(text, encoding="utf-8", newline="\n")
        print(out)
    for out in stale:
        print(f"stale: {out}", file=sys.stderr)
    if stale:
        print("Run `uv run python scripts/gen_model_docs.py` and commit the result.", file=sys.stderr)
    return 1 if stale else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
