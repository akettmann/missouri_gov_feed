{{ config(enabled=var('cl_case_bulk', false)) }}
-- Officials matched to Missouri cases in the CourtListener bulk export. Mirrors the API loader's searches
-- (src/mogov/loaders/courtlistener_cases.py) over the same people (fct_legal_careers):
--   judge     on the opinion's panel (CourtListener person id), or their surname as a whole word in the
--             judges text of a case in a court they sit on (panels are sparse for state courts)
--   attorney  "<first> <last>" as whole words in the attorneys text, for lawyers and for judges whose own
--             court CourtListener doesn't cover (trial courts)
-- Names are compared as name_key()s padded with spaces, so "Hall" doesn't match "Marshall".
-- Surnames repeat across generations on the same court (a 1910 Judge Smith on the 8th Circuit, fathers and
-- sons on the Court of Appeals), so judges-text matches only count from the judge's first known judicial
-- start date (fct_office_history, else dim_official.current_term_start); without one, panel matches only.
-- Attorney matches start at var case_history_min_year (default 1975): earlier namesakes aren't them.
with searched as (
    select
        o.official_id,
        o.office,
        {{ mogov.name_key('o.family_name') }} as family_key,
        {{ mogov.name_key(dbt.split_part('o.given_name', "' '", 1) ~ " || ' ' || o.family_name") }} as full_key,
        max(case when l.legal_role = 'lawyer' then 1 else 0 end) as is_lawyer
    from {{ ref('fct_legal_careers') }} as l
    inner join {{ ref('dim_official') }} as o on l.official_id = o.official_id
    where o.family_name is not null and o.family_name <> ''
    group by 1, 2, 3, 4
),

judicial_start as (
    select
        s.official_id,
        coalesce(min(h.start_date), max(o.current_term_start)) as start_date
    from searched as s
    inner join {{ ref('dim_official') }} as o on s.official_id = o.official_id
    left join {{ ref('fct_office_history') }} as h
        on
            s.official_id = h.official_id
            and (
                lower(h.office_title) like '%judge%'
                or lower(h.office_title) like '%justice%'
                or lower(h.office_title) like '%court%'
            )
    group by 1
),

judge_courts as (
    select
        office,
        court_id
    from {{ ref('mo_courts') }}
),

cases as (
    select
        cluster_id,
        court_id,
        date_filed,
        ' ' || {{ mogov.name_key('judges_text') }} || ' ' as judges_key,
        ' ' || {{ mogov.name_key('attorneys_text') }} || ' ' as attorneys_key
    from {{ ref('int_courtlistener__mo_cases') }}
),

on_panel as (
    select
        p.official_id,
        pn.cluster_id
    from {{ ref('stg_courtlistener__mo_cluster_panel') }} as pn
    inner join {{ ref('int_courtlistener__official_people') }} as p on pn.cl_person_id = p.cl_person_id
    inner join searched as s on p.official_id = s.official_id
),

named_judge as (
    select
        s.official_id,
        c.cluster_id
    from searched as s
    inner join judge_courts as jc on s.office = jc.office
    inner join judicial_start as js on s.official_id = js.official_id
    inner join cases as c on jc.court_id = c.court_id
    where
        c.judges_key like '% ' || s.family_key || ' %'
        and c.date_filed >= js.start_date
),

attorney as (
    select
        s.official_id,
        c.cluster_id
    from searched as s
    inner join cases as c on c.attorneys_key like '% ' || s.full_key || ' %'
    where
        (s.is_lawyer = 1 or s.office not in (select jc.office from judge_courts as jc))
        and c.date_filed >= cast('{{ var("case_history_min_year", 1975) }}-01-01' as date)
)

select
    official_id,
    'judge' as role,
    cluster_id,
    'panel' as matched_by
from on_panel
union all
select
    n.official_id,
    'judge' as role,
    n.cluster_id,
    'judges text' as matched_by
from named_judge as n
where
    not exists (
        select 1 from on_panel as p
        where p.official_id = n.official_id and p.cluster_id = n.cluster_id
    )
union all
select
    official_id,
    'attorney' as role,
    cluster_id,
    'attorneys text' as matched_by
from attorney
