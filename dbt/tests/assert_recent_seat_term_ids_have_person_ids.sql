-- Every Open States id whose seat-term ran past January 15, 2015 (the earliest year int_officials__identity_terms
-- covers, two years before the first House roster) has a person_ids row (#512). A term with an undated start used to
-- be dropped from the identity evidence, so 22 senators of 2017-2023 and two 2015 resignations had none.
-- Terms that start after December 31 of the latest House roster year are left out: Open States lists the next class
-- before the House roster has that session, and identity evidence only reaches the roster years.
with latest as (
    select max(session_year) as year from {{ ref('int_mo_house__member_seat_keys') }}
)

select
    t.openstates_id,
    t.full_name
from {{ ref('int_mo_legislators__seat_terms') }} as t
cross join latest as l
left join {{ ref('int_officials__person_ids') }} as x on t.openstates_id = x.alias_id
where
    t.end_date > {{ dbt.safe_cast("'2015-01-15'", 'date') }}
    and t.start_date
    <= {{ dbt.safe_cast(dbt.concat([dbt.safe_cast('l.year', dbt.type_string()), "'-12-31'"]), 'date') }}
    and x.alias_id is null
