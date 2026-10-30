-- Sanity bounds for who an audit of a statewide office is credited to (from 1999, the first audit year):
--   * every statewide audit has at least one officeholder (each office has had a holder at all times);
--   * no audit has more than 4 (a window is at most the audit period or two years: even with mid-term hand-overs
--     and a hand-over year at each end, that is 3-4 people; more means a lost term-end rule or a wrong office list).
select
    r.report_number as problem_key,
    case
        when r.officeholder_count = 0 then 'statewide audit without an officeholder'
        else 'more than 4 officeholders'
    end as problem
from {{ ref('fct_audit_reports') }} as r
where
    r.entity_type = 'statewide_office'
    and (r.officeholder_count = 0 or r.officeholder_count > 4)
