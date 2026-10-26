-- Which bill each state vote was on, so votes can be grouped by bill subject (fct_bill_subjects).
--   House roll calls: the bill XML names the roll-call PDF, which is the vote_id (exact). Roll calls the XML
--   doesn't name (all votes on Senate bills, some on House bills) fall back to the measure printed on the PDF
--   ("HCS HB 2", "SS SCS SBs 49 & 118"): every bill number it names, matched to that session's bills.
--   Senate journal votes: the vote's measure ("HB 2", "SB 974") read from the journal text, matched to that
--   year's regular-session bill (House bills from the House export, Senate bills from the topical index).
--   Re-listed bills (status 'relisted for governor message', int_bills__status) are never linked: the House lists
--   the previous session's appropriation bill again only to record the governor's Art. IV s.27 message, so it
--   has no floor action and a vote cannot have been on it. Their votes link to nothing here rather than to a
--   stub (the original lives in the earlier session, and is linked only when its own roll calls name it).
with relisted as (
    select
        session_code,
        bill
    from {{ ref('int_bills__status') }}
    where status = 'relisted for governor message'
),

bills as (
    select
        h.session_code,
        h.bill
    from {{ ref('stg_mo_house__bills') }} as h
    left join relisted as rl on h.session_code = rl.session_code and h.bill = rl.bill
    where rl.bill is null
    union
    select
        t.session_code,
        t.bill
    from {{ ref('stg_mo_senate__bill_topics') }} as t
    left join relisted as rl on t.session_code = rl.session_code and t.bill = rl.bill
    where t.bill like 'S%' and rl.bill is null
),

bill_keys as (
    select
        session_code,
        bill,
        {{ mogov.regex_extract('bill', '^([A-Z]+)') }} as bill_type,
        {{ mogov.regex_extract('bill', '([0-9]+)$') }} as bill_number
    from bills
),

{% set measure_bills = '(^|[ ,])(HJR|HCR|HCB|HB|HR|SJR|SCR|SB)S? +([0-9]+( *(&|,|AND) *[0-9]+)*)' %}
house_measures as (
    -- the measure's bill type and its numbers, space-padded: "SS SCS SBs 49 & 118" -> SB, " 49 118 "
    select
        rollcall_url,
        session_code,
        {{ mogov.regex_extract('upper(measure)', measure_bills, 2) }} as bill_type,
        ' '
        || trim({{ mogov.regex_replace_all(mogov.regex_extract('upper(measure)', measure_bills, 3), '[^0-9]+', ' ') }})
        || ' ' as bill_numbers
    from {{ ref('stg_mo_house__rollcalls') }}
    where rollcall_url not in (
        select l.rollcall_url
        from {{ ref('stg_mo_house__bill_rollcalls') }} as l
        where l.rollcall_url is not null
    )
)

select distinct
    'state_house' as chamber,
    r.rollcall_url as vote_id,
    r.session_code,
    r.bill,
    r.bill_version,
    'roll-call link' as matched_by
from {{ ref('stg_mo_house__bill_rollcalls') }} as r
left join relisted as rl on r.session_code = rl.session_code and r.bill = rl.bill
where r.rollcall_url is not null and rl.bill is null

union all

select distinct
    'state_house' as chamber,
    m.rollcall_url as vote_id,
    b.session_code,
    b.bill,
    cast(null as {{ dbt.type_string() }}) as bill_version,
    'measure text' as matched_by
from house_measures as m
inner join bill_keys as b
    on
        m.session_code = b.session_code
        and m.bill_type = b.bill_type
        and m.bill_numbers like '% ' || b.bill_number || ' %'

union all

select distinct
    'state_senate' as chamber,
    v.vote_id,
    b.session_code,
    b.bill,
    cast(null as {{ dbt.type_string() }}) as bill_version,
    'measure text' as matched_by
from {{ ref('int_mo_senate__votes') }} as v
inner join bills as b
    on
        replace(v.measure, ' ', '') = b.bill
        and {{ dbt.right(dbt.safe_cast('extract(year from v.vote_date)', dbt.type_string()), 2) }} || '1'
        = b.session_code
