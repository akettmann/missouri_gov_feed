-- Sitting federal judges in Missouri: E.D./W.D. Mo. district judges, plus Eighth Circuit judges whose
-- FJC career record mentions Missouri (the FJC has no duty-station field, so this is labeled, not assumed).
with appts as (
    select
        *,
        case
            when court_name = 'U.S. District Court for the Eastern District of Missouri' then 'moed'
            when court_name = 'U.S. District Court for the Western District of Missouri' then 'mowd'
            when court_name = 'U.S. Court of Appeals for the Eighth Circuit' then 'ca8'
        end as court_key
    from {{ ref('stg_fjc__appointments') }}
),

sitting as (
    select *
    from appts
    where
        court_key is not null
        and termination_date is null
        and (court_key <> 'ca8' or professional_career like '%Missouri%')
)

-- Some district judges hold joint E.D./W.D. Missouri commissions: one row per judge.
select
    'fjc:' || fjc_nid as official_id,
    fjc_nid,
    max(trim(
        coalesce(given_name, '') || ' ' || coalesce(middle_name || ' ', '') || family_name
        || coalesce(' ' || suffix, '')
    )) as full_name,
    max(given_name) as given_name,
    max(family_name) as family_name,
    'federal' as level,
    max(case court_key when 'ca8' then 'us_court_of_appeals' else 'us_district_court' end) as office,
    case
        when max(case when court_key = 'ca8' then 1 else 0 end) = 1
            then 'Judge, U.S. Court of Appeals for the Eighth Circuit (Missouri career ties)'
        when count(distinct court_key) > 1
            then 'Judge, U.S. District Courts for the Eastern and Western Districts of Missouri'
        else 'Judge, ' || max(court_name)
    end as office_title,
    case when count(distinct court_key) > 1 then 'moed+mowd' else max(court_key) end as court_id,
    min(commission_date) as current_term_start,
    cast(null as date) as current_term_end,
    max(senior_status_date) as senior_status_date,
    max(appointing_president) as appointing_president,
    max(appointing_party) as appointing_party,
    max(aba_rating) as aba_rating,
    max(professional_career) as professional_career
from sitting
group by fjc_nid
