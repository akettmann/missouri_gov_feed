-- Federal judges' disclosure line items with the report they come from and the judge's FJC id.
select
    d.cl_person_id,
    p.fjc_id,
    d.report_year,
    d.document_url,
    i.item_id,
    i.item_kind,
    i.description,
    i.amount_code,
    i.detail,
    i.is_redacted,
    i.is_garbled
from {{ ref('stg_courtlistener__judge_disclosure_items') }} as i
inner join {{ ref('stg_courtlistener__judge_disclosures') }} as d on i.disclosure_id = d.disclosure_id
inner join {{ ref('stg_courtlistener__people') }} as p on d.cl_person_id = p.cl_person_id
