-- All sitting judges we track: Missouri state judges (Official Manual, latest edition) and federal judges
-- seated in Missouri (FJC).
with latest_edition as (
    select max(edition) as edition from {{ ref('int_judges__state_index') }}
),

state_judges as (
    select
        'mojudge:' || {{ mogov.name_key("j.full_name || ' ' || j.office || ' ' || coalesce(j.circuit, '')") }}
            as official_id,
        j.full_name,
        j.given_names as given_name,
        j.family_name,
        'state' as level,
        j.office,
        j.office_title,
        j.circuit as district,
        cast(null as date) as current_term_start,
        cast(null as date) as current_term_end,
        'bluebook ' || j.edition as source
    from {{ ref('int_judges__state_index') }} as j
    inner join latest_edition as e on j.edition = e.edition
),

federal_judges as (
    select
        official_id,
        full_name,
        given_name,
        family_name,
        level,
        office,
        office_title,
        court_id as district,
        current_term_start,
        current_term_end,
        'fjc' as source
    from {{ ref('int_judges__federal') }}
)

select * from state_judges
union all
select * from federal_judges
