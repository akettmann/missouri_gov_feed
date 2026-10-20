"""Write the filer lists to attach to the personal financial disclosure requests (docs/sunshine_requests.md).
Run from the repo root after a dbt build:

    uv run python scripts/sunshine_filer_lists.py [--years 5] [--out data/sunshine]

Filing officers keep statements for five years, and a statement covers the previous calendar year, so the
lists name everyone who held the office in any of the last `--years` full calendar years, current or former:

  mec_filers.csv    legislators (Open States seat-terms, so former members are included) and statewide
                    officers (statewide_officials seed: current officers only, so add statewide officers who
                    left in those years by hand), for the Missouri Ethics Commission
  clerk_filers.csv  state judges, for the Clerk of the Supreme Court. Current judges only: former judges are
                    not in the data, so add anyone who left the bench in those years by hand
"""

import argparse
import os
from datetime import date
from pathlib import Path

import duckdb

JUDGE_OFFICES = ("mo_supreme_court", "mo_court_of_appeals", "mo_circuit_judge", "mo_associate_circuit_judge")

MEC_SQL = """
with legislators as (
    select
        full_name,
        case chamber when 'upper' then 'State Senator' else 'State Representative' end as office_title,
        cast(district_number as varchar) as district,
        party,
        nullif(cast(start_date as date), date '1900-01-01') as term_start,  -- Open States' "unknown"
        nullif(cast(end_date as date), date '9999-12-31') as term_end
    from intermediate.int_mo_legislators__seats
),

statewide as (
    select
        name as full_name,
        office_title,
        cast(null as varchar) as district,
        party,
        cast(term_start as date) as term_start,
        cast(term_end as date) as term_end
    from reference.statewide_officials
)

select
    full_name,
    office_title,
    district,
    party,
    min(term_start) as term_start,
    case when bool_or(term_end is null) then null else max(term_end) end as term_end,
    case when bool_or(term_end is null or term_end >= current_date) then 'current' else 'former' end as status
from (select * from legislators union all select * from statewide)
where coalesce(term_start, $first_day) <= $last_day and (term_end is null or term_end >= $first_day)
group by full_name, office_title, district, party
order by office_title, try_cast(district as integer), full_name
"""

CLERK_SQL = f"""
select full_name, office_title, district
from marts.dim_official
where office in {JUDGE_OFFICES}
order by office, try_cast(district as integer), full_name
"""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--years", type=int, default=5, help="full calendar years to cover (default 5)")
    parser.add_argument("--out", type=Path, default=Path("data/sunshine"))
    args = parser.parse_args()

    this_year = date.today().year
    first_day, last_day = date(this_year - args.years, 1, 1), date(this_year - 1, 12, 31)
    args.out.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(os.environ.get("MOGOV_DB", "data/mogov.duckdb"), read_only=True)

    mec = con.sql(MEC_SQL, params={"first_day": first_day, "last_day": last_day})
    mec.write_csv(str(args.out / "mec_filers.csv"))
    clerk = con.sql(CLERK_SQL)
    clerk.write_csv(str(args.out / "clerk_filers.csv"))

    current = con.sql(
        f"select count(*) from marts.dim_official where level = 'state' and office not in {JUDGE_OFFICES}"
    ).fetchone()[0]
    counts = dict(con.sql("select status, count(*) from mec group by status").fetchall())
    print(f"filing years {first_day.year}-{last_day.year}")
    n_current, n_former = counts.get("current", 0), counts.get("former", 0)
    print(f"mec_filers.csv: {n_current} current (dim_official has {current}), {n_former} former")
    print(f"clerk_filers.csv: {con.sql('select count(*) from clerk').fetchone()[0]} current judges")
    print("add by hand: statewide officers and judges who left office in those years")


if __name__ == "__main__":
    main()
