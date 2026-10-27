-- Where each bill stands: House bills (the House XML export's actions), Senate bills that reached the House (the
-- same export's SenateActList: House-side and governor actions only; a Senate bill listed there has passed the
-- Senate), and every Senate bill the Senate's own action history covers (stg_mo_senate__bill_actions, #588),
-- including the ones that never left the Senate. A bill in both feeds takes the furthest stage of either (the flags
-- are max() over both). A Senate bill has a row only when one of the two feeds has an action for it: a listed bill
-- whose Actions tab was not landed (mo_senate_bills.fragment_rejected, #637) has none, so its status stays null
-- (unknown) rather than a stage. The Senate's wording is mapped to the stage flags by the seed
-- mo_senate_action_flags (one row per phrasing; an unmapped action counts for no stage). The House XML's wording is
-- matched below.
--   status   the furthest stage the actions record: introduced, in committee, reported do pass, perfected, passed
--            one chamber, passed both chambers, truly agreed, then signed / signed with line-item vetoes / vetoed /
--            veto overridden; resolutions: adopted. withdrawn and defeated when the bill stopped there.
--            combined into another bill when the Senate's history says "Bill Combined (w/SCS SBs ...)": its content
--            went into a substitute for other bills (#750). It never passed on its own number, and whether that
--            content became law is on the vehicle bill, so this is not enacted; its outcome follows the usual rules
--            (failed once the session is over), which is a policy question (#750). It ranks below truly agreed /
--            adopted and above passed both chambers.
--            relisted for governor message when every recorded action is the governor's Art. IV, s. 27 message
--            (the budget/withholding message). These are not new bills: the House relists the previous regular
--            session's appropriation bills (same bill number, bill string and effective date; LR numbers from 241
--            on) under the new session, only to record that message. The real history, and the outcome, live on
--            the original row; relisted_from_session_code names its session.
--   outcome  null for relisted for governor message; otherwise enacted (signed, line-item vetoed, veto overridden, or
--            truly agreed and delivered to the Secretary of State without a signature), vetoed,
--            sent to voters (truly agreed joint resolutions), adopted
--            (resolutions), awaiting governor (truly agreed this year, no governor action yet), no governor action
--            recorded (truly agreed in an earlier year, but neither feed lists a governor action; the House's list
--            of a Senate bill can stop at the speaker's signature, which the Senate's own history fills in), pending
--            (session still open), failed (session over
--            without passing).
--   passed_house  true when the actions record the House's Third Read and Passed (or Adopted); a bill that passed the
--            House and then stopped (withdrawn, defeated in the Senate) is still true. In the House XML a Senate
--            bill's House action counts only when it was amended and passed again here; the Senate's own history
--            records "H Third Read and Passed" for every Senate bill the House passed.
--   relisted_from_session_code  for a relisting, the previous regular session whose bill (same number and bill
--            string) it repeats; null for other bills, and for a relisting whose original isn't loaded
--            (2017's 15 repeat the 2016 session, 161).
-- A session is over once its year has ended; a regular session also once June starts (it adjourns in mid-May) and
-- an extraordinary session 30 days after its last action (the latest of either feed). var as_of_date pins "today"
-- (unit tests). action_count and the governor-message count come from the House XML's actions only: they drive the
-- relisting rule, which is about House appropriation bills.
{% set as_of = "cast('" ~ var('as_of_date') ~ "' as date)" if var('as_of_date', none) else 'current_date' %}

with house_actions as (
    select
        session_code,
        bill,
        listed_in,
        action_date,
        description
    from {{ ref('stg_mo_house__bill_actions') }}
),

-- The Senate's own history: one row per (action, matching seed pattern); an action no pattern matches keeps one
-- row with a null flag. A phrasing can carry two flags (the House's adoption completes a Senate concurrent
-- resolution).
senate_actions as (
    select
        a.session_code,
        a.bill,
        a.action_date,
        m.flag as senate_flag
    from {{ ref('stg_mo_senate__bill_actions') }} as a
    left join {{ ref('mo_senate_action_flags') }} as m
        on
            lower(a.action) like lower(m.action_pattern)
            and (m.bill_type = 'any' or m.bill_type = {{ mogov.regex_extract('a.bill', '^([A-Z]+)') }})
    where a.session_code is not null
),

actions as (
    select
        session_code,
        bill,
        listed_in,
        action_date,
        description,
        cast(null as {{ dbt.type_string() }}) as senate_flag
    from house_actions
    union all
    select
        session_code,
        bill,
        'senate_bill_actions' as listed_in,
        action_date,
        cast(null as {{ dbt.type_string() }}) as description,
        senate_flag
    from senate_actions
),

flags as (
    select
        session_code,
        bill,
        max(case when listed_in = 'senate_act_list' then 1 else 0 end) as reached_house_from_senate,
        max(action_date) as last_action_date,
        sum(case when listed_in = 'senate_bill_actions' then 0 else 1 end) as action_count,
        sum(case
            when description like 'Message Received from the Governor, pursuant to Article IV, Section 27%'
                then 1
            else 0
        end) as governor_message_count,
        max(case
            when description like 'Referred:%' or description like '%read and referred%' or senate_flag = 'referred'
                then 1
            else 0
        end) as referred,
        max(case
            when description like '%Reported Do Pass%' or description like '%Voted Do Pass%' or senate_flag = 'reported'
                then 1
            else 0
        end) as reported,
        max(case
            when description like 'Perfected%' or description like 'Re-Perfected%' or senate_flag = 'perfected' then 1
            else 0
        end) as perfected,
        max(case
            when
                description like 'Third Read and Passed%(H)' or description like 'Third Read and Adopted (H)'
                or senate_flag = 'passed_house'
                then 1
            else 0
        end) as passed_house,
        max(case
            when
                description like 'Third Read and Passed%(S)' or description like 'Third Read and Adopted (S)'
                or senate_flag = 'passed_senate'
                then 1
            else 0
        end) as passed_senate,
        max(case when description like 'Third Read and Defeated%' or senate_flag = 'defeated' then 1 else 0 end)
            as defeated,
        max(case when senate_flag = 'combined' then 1 else 0 end) as combined,
        max(case when description in ('Withdrawn (H)', 'Withdrawn (S)') or senate_flag = 'withdrawn' then 1 else 0 end)
            as withdrawn,
        max(case when description in ('Adopted (H)', 'Adopted (S)') or senate_flag = 'adopted' then 1 else 0 end)
            as adopted,
        max(
            case
                when description = 'Truly Agreed To and Finally Passed' or senate_flag = 'truly_agreed' then 1 else 0
            end
        )
            as truly_agreed,
        max(case
            when
                description like 'Approved by Governor%' or description like 'Approved by the Lieutenant-Governor%'
                or senate_flag = 'approved'
                then 1
            else 0
        end) as approved,
        max(
            case when description like 'Vetoed in Part by Governor%' or senate_flag = 'vetoed_in_part' then 1 else 0 end
        )
            as vetoed_in_part,
        max(case when description like 'Vetoed by Governor%' or senate_flag = 'vetoed' then 1 else 0 end) as vetoed,
        max(case when description like 'Passed over Veto%' or senate_flag = 'veto_overridden' then 1 else 0 end)
            as veto_overridden,
        max(
            case
                when
                    description like 'Delivered to Secretary of State%' or senate_flag = 'delivered_to_sos'
                    then 1
                else 0
            end
        )
            as delivered_to_sos
    from actions
    group by session_code, bill
),

staged as (
    select
        *,
        {{ mogov.regex_extract('bill', '^([A-Z]+)') }} as bill_type,
        2000 + {{ dbt.safe_cast('left(session_code, 2)', dbt.type_int()) }} as session_year,
        -- a Senate bill in the House's list has passed the Senate
        case when passed_senate = 1 or reached_house_from_senate = 1 then 1 else 0 end as passed_senate_any
    from flags
),

staged_status as (
    select
        *,
        case
            when action_count > 0 and governor_message_count = action_count then 'relisted for governor message'
            when veto_overridden = 1 then 'veto overridden'
            when vetoed_in_part = 1 then 'signed with line-item vetoes'
            when approved = 1 then 'signed'
            when vetoed = 1 then 'vetoed'
            when truly_agreed = 1 then 'truly agreed'
            when adopted = 1 then 'adopted'
            when combined = 1 then 'combined into another bill'
            when passed_house = 1 and passed_senate_any = 1 then 'passed both chambers'
            when withdrawn = 1 then 'withdrawn'
            when defeated = 1 and passed_house + passed_senate_any = 0 then 'defeated'
            when passed_house = 1 or passed_senate_any = 1 then 'passed one chamber'
            when perfected = 1 then 'perfected'
            when reported = 1 then 'reported do pass'
            when referred = 1 then 'in committee'
            else 'introduced'
        end as status,
        case
            when session_year < extract(year from {{ as_of }}) then true
            when right(session_code, 1) = '1' then extract(month from {{ as_of }}) >= 6
            else last_action_date < {{ dbt.dateadd('day', -30, as_of) }}
        end as is_session_over
    from staged
),

-- A relisting repeats the previous regular session's bill: same number, same bill string. Regular sessions
-- end in 1 (251 is 2025's, 241 is 2024's), so the prior one is the year before with the same suffix.
relisting_links as (
    select
        r.session_code,
        r.bill,
        orig.session_code as relisted_from_session_code
    from staged_status as r
    inner join {{ ref('stg_mo_house__bills') }} as cur
        on r.session_code = cur.session_code and r.bill = cur.bill
    inner join {{ ref('stg_mo_house__bills') }} as orig
        on
            orig.session_code = {{ dbt.concat([dbt.safe_cast('r.session_year - 2001', dbt.type_string()), "'1'"]) }}
            and r.bill = orig.bill
            and cur.current_bill_string = orig.current_bill_string
    where r.status = 'relisted for governor message' and right(r.session_code, 1) = '1'
)

select
    s.session_code,
    s.session_year,
    s.bill,
    s.bill_type,
    s.status,
    case
        -- the outcome belongs to the original bill in the previous session; don't call the relisting failed
        when s.status = 'relisted for governor message' then cast(null as {{ dbt.type_string() }})
        when s.status in ('signed', 'signed with line-item vetoes', 'veto overridden') then 'enacted'
        when s.status = 'vetoed' then 'vetoed'
        when s.truly_agreed = 1 and s.bill_type in ('HJR', 'SJR') then 'sent to voters'
        when s.truly_agreed = 1 and s.bill_type in ('HCR', 'SCR') then 'adopted'
        when s.status = 'adopted' then 'adopted'
        when s.truly_agreed = 1 and s.delivered_to_sos = 1 then 'enacted'
        when s.truly_agreed = 1 and s.session_year = extract(year from {{ as_of }}) then 'awaiting governor'
        -- the House's list of Senate bills can stop at the speaker's signature (2024 SB 727, signed into law)
        when s.truly_agreed = 1 then 'no governor action recorded'
        when not s.is_session_over then 'pending'
        else 'failed'
    end as outcome,
    s.is_session_over,
    s.passed_house = 1 as passed_house,
    s.last_action_date,
    l.relisted_from_session_code
from staged_status as s
left join relisting_links as l on s.session_code = l.session_code and s.bill = l.bill
