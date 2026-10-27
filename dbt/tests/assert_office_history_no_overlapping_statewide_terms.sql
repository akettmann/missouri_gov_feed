-- No official holds two overlapping rows for the same statewide office (#760). The same term arrives from several
-- sources under different titles ("Governor" in the statewide_officials seed, "Governor of Missouri" in Wikidata) and
-- dates a day apart; fct_office_history keeps one. One term ending the day the next starts (Malek's 2023 appointment
-- and the 2025 term) is not an overlap. Fails with each pair that still overlaps.
with statewide as (
    select
        official_id,
        office_title,
        start_date,
        coalesce(end_date, {{ dbt.safe_cast("'9999-12-31'", 'date') }}) as end_date,
        source,
        {{ mogov.statewide_office_key('office_title') }} as office_key
    from {{ ref('fct_office_history') }}
)

select
    a.official_id,
    a.office_key,
    a.office_title as title_a,
    a.source as source_a,
    a.start_date as start_a,
    b.office_title as title_b,
    b.source as source_b,
    b.start_date as start_b
from statewide as a
inner join statewide as b
    on
        a.official_id = b.official_id
        and a.office_key = b.office_key
        and a.start_date < b.end_date
        and a.end_date > b.start_date
        and (a.start_date < b.start_date or (a.start_date = b.start_date and a.office_title < b.office_title))
where {{ mogov.is_statewide_office_key('a.office_key') }}
