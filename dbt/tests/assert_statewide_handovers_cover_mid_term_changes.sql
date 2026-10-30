-- Sanity check on the hand-over dates (#733): from 2000 on, a Manual term that starts or ends in a year with no
-- regular inauguration (2017, 2021, 2025; the auditor's 2019, 2023) is a mid-term change, and the Manual dates it
-- only to the year. Without a statewide_office_handovers row giving the date, fct_audit_report_officeholders credits
-- both holders for that whole year. A term starting in an inauguration year can also be mid-year (Hanaway,
-- 2025-09-08), which this test cannot see when only two terms meet in that year; the seed row is still needed.
-- A mid-year change inside an inauguration year does show when it adds a third term to the year: the 2015 auditor
-- changes (Schweich died, Watson interim, Galloway appointed) put three terms in 2015, and each side of the year
-- that has no dated seed row is reported (a second query below).
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

union all

-- an inauguration year (from 2000) in which more than two terms of an office start or end is a mid-year change: the
-- regular hand-over has one term ending and one starting
select
    b.office || ' ' || b.full_name as problem_key,
    'term meets an inauguration year with more than two terms and has no dated start or end in the seed' as problem
from {{ ref('int_bluebook__statewide_officeholders') }} as b
left join {{ ref('statewide_office_handovers') }} as h
    on
        b.office = h.office
        and b.term_start_year = h.term_start_year
        and {{ mogov.name_key(mogov.regex_extract('b.full_name', '([^ ]+)$')) }} = {{ mogov.name_key('h.family_name') }}
inner join (
    select
        office,
        term_year
    from (
        select
            office,
            term_start_year as term_year
        from {{ ref('int_bluebook__statewide_officeholders') }}
        union all
        select
            office,
            term_end_year as term_year
        from {{ ref('int_bluebook__statewide_officeholders') }}
    ) as years
    where term_year >= 2000 and mod(term_year, 4) = case office when 'state_auditor' then 3 else 1 end
    group by office, term_year
    having count(*) > 2
) as busy
    on
        b.office = busy.office
        and busy.term_year in (b.term_start_year, b.term_end_year)
where
    (b.term_start_year = busy.term_year and h.term_start is null)
    or (b.term_end_year = busy.term_year and h.term_end is null)
