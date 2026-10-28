-- The bills that enacted, amended or repealed each RSMo section, one row per section and bill link
-- (fct_bill_statute_links: session, bill, section, change), shaped for a statute section page. A bill in fct_bills
-- (in_fct_bills, 2017 onward) carries its short title, outcome and official page; older links show the Revisor's
-- citation only. The bill's primary sponsor (fct_bill_sponsors, sponsor_type 'Sponsor') is one person per bill today;
-- should a bill ever list several, the one with the smallest official_id (then name) is shown so a link never
-- repeats. official_id is null where the sponsor is not matched to an official, sponsor_name null where the bill has
-- no primary sponsor loaded (Senate bills, #839). A combined act's non-lead bill keeps is_lead_bill false and
-- names the lead bill in combined_into.
with sponsors as (
    select
        session_code,
        bill,
        official_id,
        sponsor_name,
        row_number() over (
            partition by session_code, bill
            order by official_id asc nulls last, sponsor_name asc, sponsor_chamber asc, sponsor_district asc
        ) as rn
    from {{ ref('fct_bill_sponsors') }}
    where sponsor_type = 'Sponsor'
)

select
    l.section_id,
    l.session_year,
    l.session_code,
    l.bill,
    l.change,
    l.citation,
    l.is_lead_bill,
    l.combined_into,
    l.in_fct_bills,
    b.short_title,
    b.outcome,
    b.source_url,
    sp.official_id,
    sp.sponsor_name
from {{ ref('fct_bill_statute_links') }} as l
left join {{ ref('fct_bills') }} as b on l.session_code = b.session_code and l.bill = b.bill
left join sponsors as sp on l.session_code = sp.session_code and l.bill = sp.bill and sp.rn = 1
