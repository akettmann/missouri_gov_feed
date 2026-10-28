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
-- State appellate and Supreme Court judges with no CourtListener person (#847) have neither, so they fall back to
-- the Missouri sources, both upper bounds on the real start (we can lose early cases, never credit a predecessor):
--   1. the first calendar year they were paid under their court's payroll title (state employee pay, from 2017)
--   2. else the year of their retention or election in their Official Manual biography
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

-- First payroll year under the title of the judge's own court (an appellate judge's earlier circuit pay doesn't count).
-- fct_salaries matches payees to officials by first-name fit, which misses "GABBERT, ANTHONY REX" for A. Rex Gabbert
-- and "POWELL, WESLEY BRENT" for W. Brent Powell, so a payee is also taken when the surname is held by exactly one
-- judge of that court and the first initials agree.
court_titles as (
    select
        'mo_court_of_appeals' as office,
        'APPELLATE JUDGE' as position_title
    union all
    select
        'mo_supreme_court' as office,
        'SUPREME COURT JUDGE' as position_title
    union all
    select
        'mo_supreme_court' as office,
        'SUPREME COURT JUDGE (CH)' as position_title
),

court_judges as (
    select
        o.official_id,
        o.office,
        {{ mogov.surname_key('o.family_name') }} as last_key,
        substr({{ mogov.name_key('o.given_name') }}, 1, 1) as first_initial,
        count(*) over (partition by o.office, {{ mogov.surname_key('o.family_name') }}) as same_surname
    from {{ ref('dim_official') }} as o
    where o.office in (select t.office from court_titles as t)
),

payroll_years as (
    select
        sal.official_id,
        sal.calendar_year
    from {{ ref('fct_salaries') }} as sal
    inner join {{ ref('dim_official') }} as o on sal.official_id = o.official_id
    inner join court_titles as t on o.office = t.office and sal.position_title = t.position_title
    union all
    select
        j.official_id,
        p.calendar_year
    from {{ ref('stg_mo_employee_pay__pay') }} as p
    inner join court_titles as t on p.position_title = t.position_title
    inner join court_judges as j
        on
            t.office = j.office
            and {{ mogov.surname_key('p.last_name') }} = j.last_key
            and substr({{ mogov.name_key('p.first_names') }}, 1, 1) = j.first_initial
    where p.agency_name = 'JUDICIARY' and j.same_surname = 1
),

payroll_start as (
    select
        official_id,
        {{ dbt.safe_cast(dbt.concat(['cast(min(calendar_year) as ' ~ dbt.type_string() ~ ')', "'-01-01'"]), 'date') }}
            as start_date
    from payroll_years
    group by 1
),

-- Retention / election dates from the Official Manual biography (fct_office_history, jurisdiction 'mo judiciary')
manual_start as (
    select
        h.official_id,
        min(h.start_date) as start_date
    from {{ ref('fct_office_history') }} as h
    where
        h.jurisdiction = 'mo judiciary'
        and h.start_date is not null
        and (lower(h.office_title) like 'retained%' or lower(h.office_title) like '%elected%')
    group by 1
),

judicial_start as (
    select
        s.official_id,
        coalesce(
            min(h.start_date),
            max(o.current_term_start),
            max(ps.start_date),
            max(ms.start_date)
        ) as start_date
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
    left join payroll_start as ps on s.official_id = ps.official_id
    left join manual_start as ms on s.official_id = ms.official_id
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
