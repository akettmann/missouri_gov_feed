-- Sanity check on Senate vote attribution (#534). int_mo_legislators__seats drops or caps a Senate term when the
-- journal roll calls attribute no (or no later) vote to it, so a name that stops matching would silently shorten a
-- real senator's term. A closed Open States Senate term that ends inside the journals' dates (first to last vote)
-- but has no attributed vote is therefore an error, except the four senators known not to have voted in the
-- journals, which begin 2017-01-04 (Open States lists their terms to 2018-12-31; the model ends them 2017-01-03).
-- Fails with one row per such term. Empty when no journal is loaded.
{{ config(severity='error') }}

with journal as (
    select
        min(vote_date) as first_date,
        max(vote_date) as last_date
    from {{ ref('int_mo_senate__votes') }}
)

select
    s.openstates_id,
    s.full_name,
    s.district_number,
    s.start_date,
    s.end_date
from {{ ref('int_mo_legislators__seats_as_given') }} as s
cross join journal as j
where
    s.chamber = 'upper'
    and s.end_date >= j.first_date
    and s.end_date <= j.last_date
    and s.openstates_id not in (
        'ocd-person/8be61611-8f4a-4318-8cd7-047b4fb282e3', -- Joseph Keaveny, SD 4
        'ocd-person/fc4fd7ed-bb0d-4d09-ac76-879751adbfc0', -- Eric Schmitt, SD 15
        'ocd-person/ff5be056-ccc0-408e-a4dd-b0a2fed76639', -- Kurt Schaefer, SD 19
        'ocd-person/d2959bf2-939f-46a0-bc69-76a6d91c1ce7' -- David Pearce, SD 21
    )
    and not exists (
        select 1
        from {{ ref('int_mo_senate__votes') }} as v
        where v.person_key = s.person_id and v.vote_date between s.start_date and s.end_date
    )
