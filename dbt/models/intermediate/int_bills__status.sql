-- Where each bill in the House XML export stands: House bills, and Senate bills once they reach the House (their
-- Senate-side history isn't in the House XML; a Senate bill listed there has passed the Senate). Senate bills that
-- never reached the House have no row.
--   status   the furthest stage the actions record: introduced, in committee, reported do pass, perfected, passed
--            one chamber, passed both chambers, truly agreed, then signed / signed with line-item vetoes / vetoed /
--            veto overridden; resolutions: adopted. withdrawn and defeated when the bill stopped there.
--   outcome  enacted (signed, line-item vetoed, veto overridden, or truly agreed and delivered to the Secretary of
--            State without a signature), vetoed, sent to voters (truly agreed joint resolutions), adopted
--            (resolutions), awaiting governor (truly agreed this year, no governor action yet), no governor action
--            recorded (truly agreed in an earlier year, but the export lists no governor action; Senate bills'
--            lists can stop at the speaker's signature), pending (session still open), failed (session over
--            without passing).
-- A session is over once its year has ended; a regular session also once June starts (it adjourns in mid-May) and
-- an extraordinary session 30 days after its last action. var as_of_date pins "today" (unit tests).
{% set as_of = "cast('" ~ var('as_of_date') ~ "' as date)" if var('as_of_date', none) else 'current_date' %}

with actions as (
    select
        session_code,
        bill,
        listed_in,
        action_date,
        description
    from {{ ref('stg_mo_house__bill_actions') }}
),

flags as (
    select
        session_code,
        bill,
        max(case when listed_in = 'senate_act_list' then 1 else 0 end) as reached_house_from_senate,
        max(action_date) as last_action_date,
        max(case when description like 'Referred:%' or description like '%read and referred%' then 1 else 0 end)
            as referred,
        max(case when description like '%Reported Do Pass%' or description like '%Voted Do Pass%' then 1 else 0 end)
            as reported,
        max(case when description like 'Perfected%' or description like 'Re-Perfected%' then 1 else 0 end)
            as perfected,
        max(case
            when description like 'Third Read and Passed%(H)' or description like 'Third Read and Adopted (H)' then 1
            else 0
        end) as passed_house,
        max(case
            when description like 'Third Read and Passed%(S)' or description like 'Third Read and Adopted (S)' then 1
            else 0
        end) as passed_senate,
        max(case when description like 'Third Read and Defeated%' then 1 else 0 end) as defeated,
        max(case when description in ('Withdrawn (H)', 'Withdrawn (S)') then 1 else 0 end) as withdrawn,
        max(case when description in ('Adopted (H)', 'Adopted (S)') then 1 else 0 end) as adopted,
        max(case when description = 'Truly Agreed To and Finally Passed' then 1 else 0 end) as truly_agreed,
        max(case
            when description like 'Approved by Governor%' or description like 'Approved by the Lieutenant-Governor%'
                then 1
            else 0
        end) as approved,
        max(case when description like 'Vetoed in Part by Governor%' then 1 else 0 end) as vetoed_in_part,
        max(case when description like 'Vetoed by Governor%' then 1 else 0 end) as vetoed,
        max(case when description like 'Passed over Veto%' then 1 else 0 end) as veto_overridden,
        max(case when description like 'Delivered to Secretary of State%' then 1 else 0 end) as delivered_to_sos
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
            when veto_overridden = 1 then 'veto overridden'
            when vetoed_in_part = 1 then 'signed with line-item vetoes'
            when approved = 1 then 'signed'
            when vetoed = 1 then 'vetoed'
            when truly_agreed = 1 then 'truly agreed'
            when adopted = 1 then 'adopted'
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
)

select
    session_code,
    session_year,
    bill,
    bill_type,
    status,
    case
        when status in ('signed', 'signed with line-item vetoes', 'veto overridden') then 'enacted'
        when status = 'vetoed' then 'vetoed'
        when truly_agreed = 1 and bill_type in ('HJR', 'SJR') then 'sent to voters'
        when truly_agreed = 1 and bill_type in ('HCR', 'SCR') then 'adopted'
        when status = 'adopted' then 'adopted'
        when truly_agreed = 1 and delivered_to_sos = 1 then 'enacted'
        when truly_agreed = 1 and session_year = extract(year from {{ as_of }}) then 'awaiting governor'
        -- the House's list of Senate bills can stop at the speaker's signature (2024 SB 727, signed into law)
        when truly_agreed = 1 then 'no governor action recorded'
        when not is_session_over then 'pending'
        else 'failed'
    end as outcome,
    is_session_over,
    last_action_date
from staged_status
