{{ config(enabled=var('cl_case_bulk', false)) }}
-- Officials matched to Missouri cases in the CourtListener bulk export. Mirrors the API loader's searches
-- (src/mogov/loaders/courtlistener_cases.py) over the same people (fct_legal_careers):
--   judge     on the opinion's panel (CourtListener person id), or their surname as a whole word in the
--             judges text of a case in a court they sit on (panels are sparse for state courts)
--   attorney  "<first> <last>" as whole words in the attorneys text, for lawyers and for judges whose own
--             court CourtListener doesn't cover (Missouri circuit courts)
-- Names are compared as name_key()s padded with spaces, so "Hall" doesn't match "Marshall".
-- Surnames repeat across generations on the same court (a 1910 Judge Smith on the 8th Circuit, fathers and
-- sons on the Court of Appeals), so judges-text matches only count from the judge's first known judicial
-- start date (fct_office_history, else dim_official.current_term_start); without one, panel matches only.
-- State appellate and Supreme Court judges with no CourtListener person (#847) have neither, so they fall back to
-- the Missouri sources, both upper bounds on the real start (we can lose early cases, we do not credit a
-- predecessor; the payroll year is only year-precise, so a start falls on January 1 of it):
--   1. the first calendar year they were paid under their court's payroll title (state employee pay, from 2017)
--   2. else the year of their retention or election in their Official Manual biography
-- A namesake paid under the same court title (any payroll payee with the judge's surname and another first initial:
-- Robert G. Dowd, Jr. was an APPELLATE JUDGE 2017-2021 beside James M. Dowd) makes a bare surname ambiguous while
-- they were paid, so such a judge starts the year after the namesake's last paid year (a later start only loses
-- cases, which keeps the upper bound). A judges text that prints the surname right after a first name or initial
-- that is not the judge's (a middle initial outside their given name, or a namesake's first name) is not them either.
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
        {{ mogov.name_key('o.given_name') }} as given_key,
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

-- Payees under the judge's own court title with the judge's surname and another first initial.
namesake_pay as (
    select distinct
        j.official_id,
        j.given_key,
        p.calendar_year,
        {{ dbt.split_part(mogov.name_key('p.first_names'), "' '", 1) }} as namesake_first
    from court_judges as j
    inner join court_titles as t on j.office = t.office
    inner join {{ ref('stg_mo_employee_pay__pay') }} as p
        on
            t.position_title = p.position_title
            and p.agency_name = 'JUDICIARY'
            and {{ mogov.surname_key('p.last_name') }} = j.last_key
            and substr({{ mogov.name_key('p.first_names') }}, 1, 1) <> j.first_initial
),

namesake_end as (
    select
        official_id,
        {{ dbt.safe_cast(
            dbt.concat(['cast(max(calendar_year) + 1 as ' ~ dbt.type_string() ~ ')', "'-01-01'"]), 'date'
        ) }} as start_date
    from namesake_pay
    group by 1
),

-- First names that, printed right before the surname, mark another person: every single letter that is not an initial
-- of the judge's given name (except J, which also ends "Wilson, J. Broniec" as a title; unless the judge's first name
-- comes right before it: "Lisa P. Page" is Lisa Page), and the first names of namesakes paid on the court. own_prefix
-- is the text that makes the token the judge's after all.
letters as (
    {% for letter in 'abcdefghiklmnopqrstuvwxyz' -%}
        select '{{ letter }}' as token
        {% if not loop.last %}union all{% endif %}
    {% endfor -%}
),

foreign_forenames as (
    select
        j.official_id,
        l.token,
        {{ dbt.split_part('j.given_key', "' '", 1) }} || ' ' || l.token as own_prefix
    from court_judges as j
    cross join letters as l
    where ' ' || j.given_key not like '% ' || l.token || '%'
    union
    select
        n.official_id,
        n.namesake_first as token,
        '#' as own_prefix
    from namesake_pay as n
    where
        length(n.namesake_first) > 1
        and ' ' || n.given_key || ' ' not like '% ' || n.namesake_first || ' %'
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

base_start as (
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

judicial_start as (
    select
        b.official_id,
        case
            when ne.start_date is not null and b.start_date < ne.start_date then ne.start_date
            else b.start_date
        end as start_date
    from base_start as b
    left join namesake_end as ne on b.official_id = ne.official_id
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
        -- a comma or semicolon stays a word, so the n of "División, Ahuja" isn't a first initial of Ahuja
        ' '
        || {{ mogov.name_key("replace(replace(judges_text, ',', ' xcommax '), ';', ' xcommax ')") }}
        || ' ' as judges_key,
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
        and not exists (
            select 1 from foreign_forenames as f
            where
                f.official_id = s.official_id
                and c.judges_key like '% ' || f.token || ' ' || s.family_key || ' %'
                and c.judges_key not like '% ' || f.own_prefix || ' ' || s.family_key || ' %'
        )
),

-- The padded LIKE below is the match rule, but a LIKE join is a nested loop (~700 people x 113k attorneys texts, #884).
-- Any key that LIKE matches has each of its words as a whole word of the text, so the equi-join on one word of the key
-- (its second word, the first word of the surname; the only word of a one-word key) picks the candidate cases, and the
-- LIKE then runs on those only: the same pairs for keys of any length.
attorney_keys as (
    select
        s.official_id,
        s.full_key,
        coalesce(nullif({{ dbt.split_part('s.full_key', "' '", 2) }}, ''), {{ dbt.split_part('s.full_key', "' '", 1) }})
            as key_word
    from searched as s
    where s.is_lawyer = 1 or s.office not in (select jc.office from judge_courts as jc)
),

attorney_words as (
    select distinct
        c.cluster_id,
        w.word
    from cases as c
    {{ mogov.cross_join_words('c.attorneys_key', 'w') }}
    where
        c.date_filed >= cast('{{ var("case_history_min_year", 1975) }}-01-01' as date)
        and w.word in (select k.key_word from attorney_keys as k)
),

attorney as (
    select
        k.official_id,
        c.cluster_id
    from attorney_keys as k
    inner join attorney_words as w on k.key_word = w.word
    inner join cases as c on w.cluster_id = c.cluster_id
    where
        c.attorneys_key like '% ' || k.full_key || ' %'
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
