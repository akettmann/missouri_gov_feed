-- Which bill each state vote was on, so votes can be grouped by bill subject (fct_bill_subjects).
--   House roll calls: the bill XML names the roll-call PDF, which is the vote_id (exact). Roll calls the XML
--   doesn't name (all votes on Senate bills, some on House bills) fall back to the measure printed on the PDF
--   ("HCS HB 2", "SS SCS SBs 49 & 118"): every bill number it names, matched to that session's bills (int_bills__list,
--   the list fct_bills uses, so special-session Senate bills the House XML lists are matched too).
--   Senate journal votes: the vote's measure ("HB 2", "SB 974") read from the journal text. Regular-session (R) and
--   veto-session (V) journals match that year's regular session (the bill list fct_bills uses, int_bills__list: House
--   bills from the House export, Senate bills from the topical index). Extraordinary-session journals (S1, S2, T1,
--   T2: the prefix does not map to a session suffix, 2018's S1 is 183 but T1 is 184) match the year's
--   extraordinary sessions (YY3, YY4) instead, where the bill has a House XML action on the vote date. A Senate
--   bill that has only House-side actions in the XML (the Senate's own steps are not listed) also matches when the
--   vote falls on or before its first recorded action, but only in the special session the vote belongs to: the one
--   whose action-date span holds the vote date, else the one that starts next (if the vote is after the year's
--   previous special session ended).
--   A vote that fits no bill, or more than one session, links to nothing.
--   Re-listed bills (status 'relisted for governor message', int_bills__status) are never linked: the House lists
--   the previous session's appropriation bill again only to record the governor's Art. IV s.27 message, so it
--   has no floor action and a vote cannot have been on it. Their votes link to nothing here rather than to a stub.
with relisted as (
    select
        session_code,
        bill
    from {{ ref('int_bills__status') }}
    where status = 'relisted for governor message'
),

bills as (
    -- the bill list fct_bills uses (int_bills__list), without the re-listings
    select
        l.session_code,
        l.bill
    from {{ ref('int_bills__list') }} as l
    left join relisted as rl on l.session_code = rl.session_code and l.bill = rl.bill
    where rl.bill is null
    group by l.session_code, l.bill
),

bill_keys as (
    select
        session_code,
        bill,
        {{ mogov.regex_extract('bill', '^([A-Z]+)') }} as bill_type,
        {{ mogov.regex_extract('bill', '([0-9]+)$') }} as bill_number
    from bills
),

senate_votes as (
    -- one row per journal vote: the bill the measure names, the two-digit year, and whether the journal is a
    -- regular (R) or veto (V) session journal, by the prefix of its file name (R/V Day..., S1Day..., T2Day...)
    select distinct
        v.vote_id,
        v.vote_date,
        replace(v.measure, ' ', '') as measure_bill,
        {{ dbt.right(dbt.safe_cast('extract(year from v.vote_date)', dbt.type_string()), 2) }} as year_code,
        coalesce(upper({{ mogov.regex_extract('v.source_url', 'Journals/([A-Za-z])') }}), 'R') in ('R', 'V')
            as regular_journal
    from {{ ref('int_mo_senate__votes') }} as v
),

special_bill_actions as (
    -- each special-session bill's first action date, and every date it has an action on
    select
        a.session_code,
        a.bill,
        a.action_date,
        min(a.action_date) over (partition by a.session_code, a.bill) as first_action_date
    from {{ ref('stg_mo_house__bill_actions') }} as a
    where {{ dbt.right('a.session_code', 1) }} in ('3', '4')
),

special_session_spans as (
    -- each special session's overall action-date span, and when the year's previous special session (by code) ended
    select
        session_code,
        start_date,
        end_date,
        lag(end_date) over (partition by substr(session_code, 1, 2) order by session_code) as prev_end_date
    from (
        select
            session_code,
            min(action_date) as start_date,
            max(action_date) as end_date
        from special_bill_actions
        group by session_code
    ) as s
),

vote_special_sessions as (
    -- the one special session a vote belongs to: the one whose span holds the vote date, else the one that starts
    -- next, if the vote is after the year's previous special session ended. The journal prefix is not used (it does
    -- not map to a session suffix). A vote in two overlapping spans belongs to neither.
    select
        v.vote_id,
        max(s.session_code) as session_code
    from senate_votes as v
    inner join special_session_spans as s
        on
            s.session_code like v.year_code || '%'
            and (
                v.vote_date between s.start_date and s.end_date
                or (v.vote_date < s.start_date and (s.prev_end_date is null or v.vote_date > s.prev_end_date))
            )
    where not v.regular_journal
    group by v.vote_id
    having count(distinct s.session_code) = 1
),

special_session_candidates as (
    -- extraordinary-session journal votes: bills of that year's YY3/YY4 sessions acted on the vote date, or (Senate
    -- bills, whose Senate-side steps the XML does not list) first acted on in the House on or after the vote date,
    -- if the session is the one the vote belongs to
    select distinct
        v.vote_id,
        a.session_code
    from senate_votes as v
    inner join special_bill_actions as a
        on
            v.measure_bill = a.bill
            and a.session_code like v.year_code || '%'
    left join vote_special_sessions as vs on v.vote_id = vs.vote_id
    where
        not v.regular_journal
        and (
            v.vote_date = a.action_date
            or (a.bill like 'S%' and v.vote_date <= a.first_action_date and vs.session_code = a.session_code)
        )
),

special_session_matches as (
    -- only votes that fit exactly one special session
    select
        vote_id,
        max(session_code) as session_code
    from special_session_candidates
    group by vote_id
    having count(distinct session_code) = 1
),

{% set measure_bills = '(^|[ ,])(HJR|HCR|HCB|HB|HR|SJR|SCR|SB)S? +([0-9]+( *(&|,|AND) *[0-9]+)*)' %}
house_measures as (
    -- the measure's bill type and its numbers, space-padded: "SS SCS SBs 49 & 118" -> SB, " 49 118 "
    select
        rollcall_url,
        session_code,
        {{ mogov.regex_extract('upper(measure)', measure_bills, 2) }} as bill_type,
        ' '
        || trim({{ mogov.regex_replace_all(mogov.regex_extract('upper(measure)', measure_bills, 3), '[^0-9]+', ' ') }})
        || ' ' as bill_numbers
    from {{ ref('stg_mo_house__rollcalls') }}
    where rollcall_url not in (
        select l.rollcall_url
        from {{ ref('stg_mo_house__bill_rollcalls') }} as l
        where l.rollcall_url is not null
    )
)

select distinct
    'state_house' as chamber,
    r.rollcall_url as vote_id,
    r.session_code,
    r.bill,
    r.bill_version,
    'roll-call link' as matched_by
from {{ ref('stg_mo_house__bill_rollcalls') }} as r
left join relisted as rl on r.session_code = rl.session_code and r.bill = rl.bill
where r.rollcall_url is not null and rl.bill is null

union all

select distinct
    'state_house' as chamber,
    m.rollcall_url as vote_id,
    b.session_code,
    b.bill,
    cast(null as {{ dbt.type_string() }}) as bill_version,
    'measure text' as matched_by
from house_measures as m
inner join bill_keys as b
    on
        m.session_code = b.session_code
        and m.bill_type = b.bill_type
        and m.bill_numbers like '% ' || b.bill_number || ' %'

union all

select distinct
    'state_senate' as chamber,
    v.vote_id,
    b.session_code,
    b.bill,
    cast(null as {{ dbt.type_string() }}) as bill_version,
    'measure text' as matched_by
from senate_votes as v
inner join bills as b
    on
        v.measure_bill = b.bill
        and v.regular_journal
        and v.year_code || '1' = b.session_code

union all

select distinct
    'state_senate' as chamber,
    v.vote_id,
    m.session_code,
    v.measure_bill as bill,
    cast(null as {{ dbt.type_string() }}) as bill_version,
    'measure text' as matched_by
-- the bill is known from its actions (special-session Senate bills are not in stg_mo_house__bills)
from senate_votes as v
inner join special_session_matches as m on v.vote_id = m.vote_id
