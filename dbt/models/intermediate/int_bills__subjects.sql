-- Subject index terms per bill from both chambers' indexes. A House bill keeps the House XML's own terms
-- (2024 sessions on); the Senate topical index fills in House bills without them (earlier sessions, when
-- the bill reached the Senate) and covers Senate bills. The two indexes tag the same House bill a little
-- differently, so they're not mixed for one bill. subject_source says which index a row comes from.
with house as (
    select distinct
        session_code,
        bill,
        subject_id,
        subject_name,
        'house' as subject_source
    from {{ ref('stg_mo_house__bill_subjects') }}
    where subject_name is not null
),

house_bills as (
    select distinct
        session_code,
        bill
    from house
),

senate as (
    select distinct
        t.session_code,
        t.bill,
        cast(null as {{ dbt.type_string() }}) as subject_id,
        t.subject_name,
        'senate' as subject_source
    from {{ ref('stg_mo_senate__bill_topics') }} as t
    left join house_bills as h on t.session_code = h.session_code and t.bill = h.bill
    where h.bill is null
)

select * from house
union all
select * from senate
