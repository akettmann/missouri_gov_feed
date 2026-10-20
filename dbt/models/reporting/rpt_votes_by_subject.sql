-- How each official voted on bills by subject: recorded votes (fct_votes) linked to bills (fct_vote_bills) and
-- the bills' subjects (fct_bill_subjects: House subject index, Senate topics). A roll call on several bills
-- with the same subject counts once, so counts are distinct roll calls. Subject names come from two indexes
-- (subject_source) and aren't merged across them.
with linked as (
    select distinct
        v.official_id,
        v.chamber,
        v.vote_id,
        v.vote_cast,
        s.subject_name,
        s.subject_source,
        vb.session_code,
        vb.bill
    from {{ ref('fct_votes') }} as v
    inner join {{ ref('fct_vote_bills') }} as vb
        on v.chamber = vb.chamber and v.vote_id = vb.vote_id
    inner join {{ ref('fct_bill_subjects') }} as s
        on vb.session_code = s.session_code and vb.bill = s.bill
)

select
    official_id,
    chamber,
    subject_name,
    subject_source,
    cast(count(distinct vote_id) as {{ dbt.type_bigint() }}) as roll_calls,
    cast(count(distinct case when vote_cast = 'yea' then vote_id end) as {{ dbt.type_bigint() }}) as yea,
    cast(count(distinct case when vote_cast = 'nay' then vote_id end) as {{ dbt.type_bigint() }}) as nay,
    cast(
        count(distinct case when vote_cast not in ('yea', 'nay') then vote_id end) as {{ dbt.type_bigint() }}
    ) as other,
    cast(count(distinct session_code || ':' || bill) as {{ dbt.type_bigint() }}) as bills,
    min(session_code) as first_session,
    max(session_code) as last_session
from linked
group by official_id, chamber, subject_name, subject_source
