-- How far each federal bill got, read from the GovInfo BILLSTATUS action codes (never the action text, except for the
-- pocket veto, which has no code of its own and does not occur in the Congresses loaded so far). Each event is read
-- from the Library of Congress's coded copy of the action (source_system 'Library of Congress'; the chamber's own
-- copy is ignored so nothing counts twice) and the first date of each code is kept, so repeated actions change
-- nothing. Codes: 8000/9000 passed/failed in House, 17000/18000 passed/failed in Senate, 28000 presented to the
-- President, 31000 vetoed, 32000/34000 passed House/Senate over the veto, 33000/35000 failed of passage in
-- House/Senate over the veto, 36000 and 41000 became Public/Private Law, E30000 "Signed by President". Committee:
-- 1010, 5000, 14000, 14900 reported; 5500, 14500 discharged.
-- `stage` is the furthest point reached: introduced, committee_reported_or_discharged, passed_one_chamber,
-- passed_both_chambers (each chamber passed a version of it; the texts may still differ, presented_to_president is
-- when they agreed), agreed_to (a simple resolution, hres or sres, agreed to in its own chamber: it never leaves
-- it), presented_to_president, vetoed (vetoed, not overridden, not law), pocket_vetoed, veto_overridden (both
-- chambers passed it over the veto but no law number is listed yet), became_law. A concurrent resolution that passed
-- both chambers is passed_both_chambers (final; it is not presented). stage_rank orders the stages in that order,
-- with the endings sharing 6 (agreed_to is 4); a failed vote does not lower the stage, see the failed dates.
-- `president_outcome` for bills presented to the President: signed, became_law_without_signature (became law, no
-- "Signed by President" action), vetoed, pocket_vetoed, veto_overridden, or presented_no_action_recorded (presented,
-- nothing after it: still pending, or the Congress ended). `veto_result` for vetoed bills: overridden,
-- override_failed_house, override_failed_senate (a vote under the 2/3 required; the veto stands),
-- override_passed_one_chamber, or no_override_vote_recorded. Whether a bill "succeeded" is the reader's choice
-- (#622): this model only says what happened.
-- A bill is also became_law when the BILLSTATUS laws list gives it a law number (has_law_number), as the staging
-- model for bills says it must; a few files list a law number without any matching action (119-hr-766 lists
-- Public Law 119-120 and its actions stop at referral), so it is became_law with no dates and no president_outcome.
with events as (
    select
        bill_id,
        min(case when action_code = '8000' then action_date end) as house_passed_date,
        min(case when action_code = '9000' then action_date end) as house_failed_date,
        min(case when action_code = '17000' then action_date end) as senate_passed_date,
        min(case when action_code = '18000' then action_date end) as senate_failed_date,
        min(case when action_code in ('1010', '5000', '14000', '14900') then action_date end) as reported_date,
        min(case when action_code in ('5500', '14500') then action_date end) as discharged_date,
        min(case when action_code = '28000' then action_date end) as presented_date,
        min(case when action_code = '31000' then action_date end) as vetoed_date,
        min(
            case
                when action_type in ('President', 'Veto') and lower(action_text) like '%pocket veto%' then action_date
            end
        ) as pocket_vetoed_date,
        min(case when action_code = '32000' then action_date end) as house_override_passed_date,
        min(case when action_code = '34000' then action_date end) as senate_override_passed_date,
        min(case when action_code = '33000' then action_date end) as house_override_failed_date,
        min(case when action_code = '35000' then action_date end) as senate_override_failed_date,
        min(case when action_code = 'E30000' then action_date end) as signed_date,
        min(case when action_code in ('36000', '41000') then action_date end) as became_law_date
    from {{ ref('stg_govinfo_billstatus__actions') }}
    where source_system = 'Library of Congress'
    group by bill_id
),

laws as (
    select distinct bill_id
    from {{ ref('stg_govinfo_billstatus__laws') }}
),

flagged as (
    select
        b.bill_id,
        b.congress,
        b.bill_type,
        b.bill_number,
        e.house_passed_date,
        e.house_failed_date,
        e.senate_passed_date,
        e.senate_failed_date,
        e.reported_date,
        e.discharged_date,
        e.presented_date,
        e.signed_date,
        e.vetoed_date,
        e.pocket_vetoed_date,
        e.house_override_passed_date,
        e.senate_override_passed_date,
        e.house_override_failed_date,
        e.senate_override_failed_date,
        e.became_law_date,
        l.bill_id is not null as has_law_number,
        coalesce(b.bill_type in ('hr', 's', 'hjres', 'sjres'), false) as goes_to_president,
        coalesce(
            e.house_override_passed_date is not null and e.senate_override_passed_date is not null, false
        ) as is_override_complete
    from {{ ref('stg_govinfo_billstatus__bills') }} as b
    left join events as e on b.bill_id = e.bill_id
    left join laws as l on b.bill_id = l.bill_id
),

staged as (
    select
        *,
        case
            when became_law_date is not null or has_law_number then 'became_law'
            when pocket_vetoed_date is not null then 'pocket_vetoed'
            when is_override_complete then 'veto_overridden'
            when vetoed_date is not null then 'vetoed'
            when presented_date is not null then 'presented_to_president'
            when bill_type in ('hres', 'sres') and coalesce(house_passed_date, senate_passed_date) is not null
                then 'agreed_to'
            when house_passed_date is not null and senate_passed_date is not null then 'passed_both_chambers'
            when coalesce(house_passed_date, senate_passed_date) is not null then 'passed_one_chamber'
            when coalesce(reported_date, discharged_date) is not null then 'committee_reported_or_discharged'
            else 'introduced'
        end as stage,
        case
            when presented_date is null and became_law_date is null then null
            when pocket_vetoed_date is not null then 'pocket_vetoed'
            when is_override_complete then 'veto_overridden'
            when vetoed_date is not null then 'vetoed'
            when became_law_date is not null and signed_date is not null then 'signed'
            when became_law_date is not null then 'became_law_without_signature'
            else 'presented_no_action_recorded'
        end as president_outcome,
        case
            when vetoed_date is null and pocket_vetoed_date is null then null
            when is_override_complete then 'overridden'
            when house_override_failed_date is not null then 'override_failed_house'
            when senate_override_failed_date is not null then 'override_failed_senate'
            when coalesce(house_override_passed_date, senate_override_passed_date) is not null
                then 'override_passed_one_chamber'
            else 'no_override_vote_recorded'
        end as veto_result
    from flagged
)

select
    bill_id,
    congress,
    bill_type,
    bill_number,
    stage,
    case stage
        when 'introduced' then 1
        when 'committee_reported_or_discharged' then 2
        when 'passed_one_chamber' then 3
        when 'passed_both_chambers' then 4
        when 'agreed_to' then 4
        when 'presented_to_president' then 5
        else 6
    end as stage_rank,
    goes_to_president,
    has_law_number,
    president_outcome,
    veto_result,
    reported_date,
    discharged_date,
    house_passed_date,
    house_failed_date,
    senate_passed_date,
    senate_failed_date,
    presented_date,
    vetoed_date,
    pocket_vetoed_date,
    house_override_passed_date,
    house_override_failed_date,
    senate_override_passed_date,
    senate_override_failed_date,
    signed_date,
    became_law_date
from staged
