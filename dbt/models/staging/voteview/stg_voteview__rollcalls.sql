-- Voteview roll calls (both chambers, loaded congresses): date, bill, question, result and vote totals.
select
    {{ dbt.safe_cast('congress', dbt.type_int()) }} as congress,
    chamber,
    {{ dbt.safe_cast('rollnumber', dbt.type_int()) }} as rollnumber,
    {{ dbt.safe_cast('date', 'date') }} as vote_date,
    {{ dbt.safe_cast('session', dbt.type_int()) }} as session,
    {{ dbt.safe_cast('yea_count', dbt.type_int()) }} as yea_count,
    {{ dbt.safe_cast('nay_count', dbt.type_int()) }} as nay_count,
    bill_number,
    vote_result,
    vote_desc,
    vote_question,
    dtl_desc
from {{ source('voteview', 'rollcalls') }}
-- House and Senate only: this file has no President rows today; any other chamber value is dropped here
-- (the source accepted_values test flags it)
where chamber in ('House', 'Senate')
