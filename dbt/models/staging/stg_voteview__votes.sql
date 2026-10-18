-- cast_code per Voteview: 1-3 yea, 4-6 nay, 7-8 present, 9 not voting, 0 not a member.
with typed as (
    select
        {{ dbt.safe_cast('congress', dbt.type_int()) }} as congress,
        chamber,
        {{ dbt.safe_cast('rollnumber', dbt.type_int()) }} as rollnumber,
        {{ dbt.safe_cast('icpsr', dbt.type_int()) }} as icpsr,
        {{ dbt.safe_cast('cast_code', dbt.type_int()) }} as cast_code
    from {{ source('raw', 'voteview_votes') }}
)

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
