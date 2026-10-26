-- cast_code per Voteview: 1-3 yea, 4-6 nay, 7-8 present, 9 not voting, 0 not a member.
with typed as (
    select
        {{ dbt.safe_cast('congress', dbt.type_int()) }} as congress,
        chamber,
        {{ dbt.safe_cast('rollnumber', dbt.type_int()) }} as rollnumber,
        {{ dbt.safe_cast('icpsr', dbt.type_int()) }} as icpsr,
        {{ dbt.safe_cast('cast_code', dbt.type_int()) }} as cast_code
    from {{ source('voteview', 'votes') }}
    -- House and Senate only; any other chamber value is dropped here (the source accepted_values test flags it)
    where chamber in ('House', 'Senate')
)

-- Voteview records the President's announced position on some roll calls as a vote row under a
-- presidential ICPSR id (99912, 99913 in the loaded data; Voteview reserves 99xxx for presidents), with the
-- chamber of the roll call. They aren't members of either chamber, so they're dropped here explicitly rather
-- than by the inner join to members downstream (941 rows in the loaded congresses).


select
    congress,
    chamber,
    rollnumber,
    icpsr,
    cast_code,
    case
        when cast_code between 1 and 3 then 'yea'
        when cast_code between 4 and 6 then 'nay'
        when cast_code in (7, 8) then 'present'
        when cast_code = 9 then 'not voting'
        else 'not a member'
    end as vote_cast
from typed
where icpsr < 99000
