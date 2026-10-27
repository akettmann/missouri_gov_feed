-- Sanity check on the hand-over dates (#733): from 2000 on, a Manual term that starts or ends in a year with no
-- regular inauguration (2017, 2021, 2025; the auditor's 2019, 2023) is a mid-term change, and the Manual dates it
-- only to the year. Without a statewide_office_handovers row giving the date, fct_audit_report_officeholders credits
-- both holders for that whole year. A term starting in an inauguration year can also be mid-year (Hanaway,
-- 2025-09-08), which this test cannot see; the seed row is still needed.
-- The 2015 interim auditor (Watson) starts in an auditor inauguration year, so the rule does not flag him.
select
    b.office || ' ' || b.full_name as problem_key,
    case
        when
            b.term_start_year >= 2000
            and mod(b.term_start_year, 4) <> case b.office when 'state_auditor' then 3 else 1 end
            and h.term_start is null
            then 'term starts outside an inauguration year with no dated start in the seed'
        else 'term ends outside an inauguration year with no dated end in the seed'
    end as problem
from {{ ref('int_bluebook__statewide_officeholders') }} as b
left join {{ ref('statewide_office_handovers') }} as h
    on
        b.office = h.office
        and b.term_start_year = h.term_start_year
        and {{ mogov.name_key(mogov.regex_extract('b.full_name', '([^ ]+)$')) }} = {{ mogov.name_key('h.family_name') }}
where
    (
        b.term_start_year >= 2000
        and mod(b.term_start_year, 4) <> case b.office when 'state_auditor' then 3 else 1 end
        and h.term_start is null
    )
    or (
        b.term_end_year >= 2000
        and mod(b.term_end_year, 4) <> case b.office when 'state_auditor' then 3 else 1 end
        and h.term_end is null
    )
