-- Sanity check (#660, #516, #547): every officeholder year from the first House roster year to the latest year has
-- both chambers in int_officeholders__years, counting distinct official_ids. The House has 163 seats and
-- the Senate 34. Fails for a year with fewer than 140 House or 30 Senate officials.
-- Guards: the whole Senate missing for 2017-2022 (#516, Open States gave those terms no dates), and the House
-- last-vote rule emptying the newest year in January before its roll calls load (#491).
-- Floors, measured on a full build (2026-10): the House minimum is 154 (2022)
-- and the Senate has 34 every year 2017-2026.
-- 140 leaves room for a year with many vacancies (#547: the old floor of 150 was only 4 under the real minimum)
-- and still catches any wholesale drop; 30 leaves 4 Senate vacancies.
-- Years come from a series, not from the rows themselves, so a year with no rows for a chamber counts as 0. The
-- series ends at the later of the newest House roster year and the newest officeholder year (#668): ending it at the
-- newest officeholder year alone would stop it a year early, and pass, if every office lost its newest year.
-- In practice the bound is the newest House roster year (2026 for both on a full build, 2026-10); the officeholder
-- branch only guards against a gap, a year with officeholders but no roster yet.
with last_years as (
    select max(session_year) as last_year from {{ ref('int_mo_house__member_identity') }}
    union all
    select max(year) as last_year from {{ ref('int_officeholders__years') }}
),

bounds as (
    select
        (select min(session_year) from {{ ref('int_mo_house__member_identity') }}) as first_year,
        (select max(last_year) from last_years) as last_year
),

years as (
    select {{ dbt.safe_cast("b.first_year + s.generated_number - 1", dbt.type_int()) }} as year
    from bounds as b
    cross join ({{ dbt_utils.generate_series(100) }}) as s
    where b.first_year + s.generated_number - 1 <= b.last_year
),

chambers as (
    select
        'state_house' as office,
        140 as min_rows
    union all
    select
        'state_senate' as office,
        30 as min_rows
),

kept as (
    select
        year,
        office,
        count(distinct official_id) as officeholder_rows
    from {{ ref('int_officeholders__years') }}
    where office in ('state_house', 'state_senate') and official_id is not null
    group by year, office
)

select
    y.year,
    c.office,
    c.min_rows,
    coalesce(k.officeholder_rows, 0) as officeholder_rows
from years as y
cross join chambers as c
left join kept as k on y.year = k.year and c.office = k.office
where coalesce(k.officeholder_rows, 0) < c.min_rows
