-- Current commercial ventures and relationships: positions held in businesses/organizations, earned
-- income sources, compensation over $5,000 from one source, business agreements, and businesses the
-- official leads per Wikidata. Personal holdings (stocks, funds) are in fct_disclosures, not here.
-- Grain: (official_id, source_item_id): the fct_disclosures item (disclosure_item_id) or the Wikidata fact.
with disclosure_ties as (
    select
        official_id,
        case
            when section in ('E: positions', 'Part 8. Positions', 'outside position') then 'position held'
            when section in ('C: earned income', 'Part 2. Earned and Non-Investment Income', 'non-investment income')
                then 'income source'
            when
                section in ('J: compensation over $5,000 from one source', 'Part 10. Compensation')
                then 'compensation source'
            when section in ('F: agreements', 'Part 9. Agreements', 'agreement') then 'agreement'
        end as tie_kind,
        description as detail,
        report_year as as_of_year,
        disclosure_type as source,
        document_url as source_url,
        disclosure_item_id as source_item_id,
        case
            when owner in ('SP', 'Spouse') then 'spouse' when
                owner in ('DC', 'Child', 'Dependent')
                then 'dependent'
            else 'self'
        end
            as whose
    from {{ ref('fct_disclosures') }}
    -- unreadable OCR text (AO-10 scans) says nothing about the tie, so it isn't one
    where not is_garbled and section in (
        'E: positions', 'Part 8. Positions', 'outside position',
        'C: earned income', 'Part 2. Earned and Non-Investment Income', 'non-investment income',
        'J: compensation over $5,000 from one source', 'Part 10. Compensation',
        'F: agreements', 'Part 9. Agreements', 'agreement'
    )
),

latest_year as (
    select
        official_id,
        max(as_of_year) as as_of_year
    from disclosure_ties
    group by 1
),

wikidata_ties as (
    select
        q.official_id,
        f.fact_kind as tie_kind,
        f.value as detail,
        cast(null as {{ dbt.type_int() }}) as as_of_year,
        'Wikidata' as source,
        'https://www.wikidata.org/wiki/' || coalesce(f.value_qid, q.qid) as source_url,
        'wikidata:' || f.qid || ':' || f.fact_kind || ':' || coalesce(f.value_qid, f.value) as source_item_id,
        'self' as whose
    from {{ ref('int_officials__wikidata') }} as q
    inner join {{ ref('stg_wikidata__facts') }} as f on q.qid = f.qid
    where f.fact_kind in (
        'employer', 'chief executive of', 'director/manager of', 'board member of',
        'chairperson of', 'founder of', 'owner of'
    )
)

select
    d.official_id,
    d.tie_kind,
    d.whose,
    d.detail,
    d.as_of_year,
    d.as_of_year = y.as_of_year as is_latest_report,
    d.source,
    d.source_url,
    d.source_item_id
from disclosure_ties as d
inner join latest_year as y on d.official_id = y.official_id

union all

select
    official_id,
    tie_kind,
    whose,
    detail,
    as_of_year,
    true as is_latest_report,
    source,
    source_url,
    source_item_id
from wikidata_ties
