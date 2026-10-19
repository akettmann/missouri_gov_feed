-- Line items from federal judges' disclosures, one shape for all parts of the report.
{% set parts = [
    ('cl_fd_investments', 'investment', 'description', "coalesce(gross_value_code, '')", "coalesce(transaction_during_reporting_period, '')"),
    ('cl_fd_positions', 'outside position', "position || ' - ' || organization_name", "''", "''"),
    ('cl_fd_agreements', 'agreement', "parties_and_terms", "''", "date_raw"),
    ('cl_fd_non_investment_income', 'non-investment income', "source_type", "income_amount", "date_raw"),
    ('cl_fd_spousal_income', 'spousal income', "source_type", "''", "date_raw"),
    ('cl_fd_gifts', 'gift', "source || ': ' || description", "value", "''"),
    ('cl_fd_debts', 'liability', "creditor_name || ' - ' || description", "value_code", "''"),
    ('cl_fd_reimbursements', 'reimbursement', "source || ': ' || coalesce(purpose, '') || ' (' || coalesce(location, '') || ')'", "''", "items_paid_or_provided"),
] %}
with items as (
    {% for table, kind, descr, amount, extra in parts %}
        select
            financial_disclosure_id as disclosure_id,
            '{{ kind }}' as item_kind,
            {{ descr }} as description,  -- noqa: AL03,RF04
            {{ amount }} as amount_code,
            {{ extra }} as detail,
            redacted = 't' as is_redacted
        from {{ source('raw', table) }}
        {% if not loop.last %}union all{% endif %}
    {% endfor %}
)

select
    d.cl_person_id,
    d.fjc_id,
    d.report_year,
    d.document_url,
    i.item_kind,
    i.description,
    i.amount_code,
    i.detail,
    i.is_redacted
from items as i
inner join {{ ref('stg_courtlistener__judge_disclosures') }} as d on i.disclosure_id = d.disclosure_id
