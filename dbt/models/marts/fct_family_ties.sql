-- Family members and their roles, especially leadership of companies/organizations.
--   Wikidata          documented relatives, any organization they lead, and offices they hold
--   Disclosures       spouse/dependent-owned positions, income and compensation on mandatory reports
--                     (e.g. a spouse's employer, a spouse's board seat)
-- Missouri business-registry officer data (SOS) would extend this but is not machine-accessible.
with wikidata as (
    select
        q.official_id,
        r.relation,
        r.relative_name,
        coalesce(r.leadership_role, case when r.relative_position is not null then 'public office' end) as role,
        coalesce(r.organization, r.relative_position) as organization,
        'Wikidata' as source,
        'https://www.wikidata.org/wiki/' || r.relative_qid as source_url
    from {{ ref('int_officials__wikidata') }} as q
    inner join {{ ref('stg_wikidata__relatives') }} as r on q.qid = r.qid
),

disclosed as (
    select
        official_id,
        whose as relation,
        cast(null as {{ dbt.type_string() }}) as relative_name,
        tie_kind as role,
        detail as organization,
        source,
        source_url
    from {{ ref('fct_commercial_ties') }}
    where whose in ('spouse', 'dependent') and is_latest_report
),

spouse_income as (
    select
        official_id,
        'spouse' as relation,
        cast(null as {{ dbt.type_string() }}) as relative_name,
        'spouse income source' as role,
        description as organization,
        disclosure_type as source,
        document_url as source_url
    from {{ ref('fct_disclosures') }}
    where section = 'spousal income' and not is_garbled  -- unreadable AO-10 OCR text
)

select distinct * from wikidata
union all
select distinct * from disclosed
union all
select distinct * from spouse_income
