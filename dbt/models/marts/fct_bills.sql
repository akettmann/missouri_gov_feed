-- Missouri House bills and resolutions per session (House XML export), with their subject index terms
-- folded into one text column for display; fct_bill_subjects has one row per term for grouping.
-- Senate bills are not in the House export and are not covered yet.
with subjects as (
    select
        session_code,
        bill,
        {{ dbt.listagg('subject_name', "'; '", "order by subject_name") }} as subjects
    from {{ ref('stg_mo_house__bill_subjects') }}
    group by session_code, bill
)

select
    b.session_code,
    b.session_year,
    b.bill,
    b.current_bill_string,
    b.short_title,
    b.long_title,
    s.subjects,
    b.last_action,
    b.proposed_effective_date,
    b.source_url
from {{ ref('stg_mo_house__bills') }} as b
left join subjects as s on b.session_code = s.session_code and b.bill = s.bill
