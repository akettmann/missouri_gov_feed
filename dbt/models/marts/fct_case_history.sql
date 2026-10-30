-- Cases involving officials who are or were judges or lawyers (CourtListener), with role and outcome.
-- role: 'judge' (authored or sat on the panel) or 'attorney' (named as counsel in the opinion).
-- Two inputs, one row per (official, role, case):
--   bulk  quarterly bulk export matched in int_courtlistener__bulk_case_matches (var cl_case_bulk)
--   api   REST search hits (courtlistener_cases loader): newer than the last snapshot, and with the
--         lead opinion's closing text when COURTLISTENER_TOKEN is set
-- outcome: a fixed vocabulary (mogov.classify_outcome) read from CourtListener's disposition when present,
-- else from decree phrases at the end of the lead opinion (API rows only), else null. disposition stays
-- verbatim beside it.
-- Caveats: surname-only judge matches can catch a same-named judge on the same court; attorney text
-- names an Attorney General on every brief their office filed (role 'attorney' = office of record).
with api as (
    select
        *,
        'api' as input
    from {{ ref('stg_courtlistener__api_cases') }}
),

cases as (
    select * from api
    {% if var('cl_case_bulk', false) %}
        union all
        select
            m.official_id,
            m.role,
            c.cluster_id,
            c.case_name,
            c.court,
            c.court_id,
            c.docket_number,
            c.date_filed,
            c.judges_text,
            c.attorneys_text,
            c.publication_status,
            c.disposition,
            null as opinion_tail,
            c.source_url,
            'bulk' as input
        from {{ ref('int_courtlistener__bulk_case_matches') }} as m
        inner join {{ ref('int_courtlistener__mo_cases') }} as c on m.cluster_id = c.cluster_id
    {% endif %}
),

-- When both have the case, an API row with outcome data (opinion text or disposition, token-only) wins;
-- otherwise the bulk row, which has the disposition field.
deduped as (
    select *
    from (
        select
            cases.*,
            row_number() over (
                partition by cases.official_id, cases.role, coalesce(cases.cluster_id, cases.source_url)
                order by
                    case
                        when
                            cases.input = 'api' and (cases.opinion_tail is not null or cases.disposition is not null)
                            then 0
                        when cases.input = 'bulk' then 1
                        else 2
                    end,
                    -- rows that still tie (an API row repeated, or two bulk matches of one cluster): a stable key
                    cases.input,
                    cases.source_url,
                    cases.docket_number,
                    cases.court_id,
                    cases.date_filed,
                    cases.case_name
            ) as rn
        from cases
    ) as ranked
    where rn = 1
)

select
    official_id,
    role,
    case_name,
    court,
    court_id,
    docket_number,
    date_filed,
    nullif(trim(coalesce(disposition, '')), '') as disposition,
    -- the disposition, classified; else decree phrases at the end of the opinion (strict phrases: it's prose);
    -- else 'other' for a disposition that fits no class (e.g. "SUSPENDED", "ELECTION RESULTS VALID")
    coalesce(
        nullif({{ mogov.classify_outcome('disposition') }}, 'other'),
        case
            when
                opinion_tail like '%AFFIRMED IN PART%' or opinion_tail like '%REVERSED IN PART%'
                then 'affirmed in part, reversed in part'
            when
                opinion_tail like '%REVERSED AND REMANDED%' or opinion_tail like '%REVERSE AND REMAND%'
                then 'reversed and remanded'
            when opinion_tail like '%VACATED%' then 'vacated'
            when opinion_tail like '%REVERSED%' then 'reversed'
            when opinion_tail like '%REMANDED%' then 'remanded'
            when opinion_tail like '%AFFIRMED%' or opinion_tail like '%IS AFFIRMED%' then 'affirmed'
            when opinion_tail like '%DISMISSED%' then 'dismissed'
            when opinion_tail like '%PERMANENT WRIT%' or opinion_tail like '%WRIT IS MADE ABSOLUTE%' then 'writ granted'
            when opinion_tail like '%WRIT%DENIED%' or opinion_tail like '%QUASHED%' then 'writ denied'
        end,
        {{ mogov.classify_outcome('disposition') }}
    ) as outcome,
    judges_text,
    attorneys_text,
    publication_status,
    source_url
from deduped
