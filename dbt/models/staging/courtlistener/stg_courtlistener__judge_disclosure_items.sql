-- Line items from federal judges' AO-10 reports, one shape for every part of the report (investments,
-- positions, agreements, income, gifts, liabilities, reimbursements).
-- Scanned reports are OCR text, and some items are unreadable: is_garbled flags them (mogov.is_garbled_text).
-- Investment descriptions are tickers and fund codes, which read as garbled, so they are never flagged.
{% set parts = [
    ('fd_investments', 'investment', 'description', "coalesce(gross_value_code, '')", "coalesce(transaction_during_reporting_period, '')"),
    ('fd_positions', 'outside position', "position || ' - ' || organization_name", "''", "''"),
    ('fd_agreements', 'agreement', "parties_and_terms", "''", "date_raw"),
    ('fd_non_investment_income', 'non-investment income', "source_type", "income_amount", "date_raw"),
    ('fd_spousal_income', 'spousal income', "source_type", "''", "date_raw"),
    ('fd_gifts', 'gift', "source || ': ' || description", "value", "''"),
    ('fd_debts', 'liability', "creditor_name || ' - ' || description", "value_code", "''"),
    ('fd_reimbursements', 'reimbursement', "source || ': ' || coalesce(purpose, '') || ' (' || coalesce(location, '') || ')'", "''", "items_paid_or_provided"),
] %}
with items as (
    {% for table, kind, descr, amount, extra in parts %}
        select
            financial_disclosure_id as disclosure_id,
            '{{ kind }}' || ':' || id as item_id,  -- ids are unique per CourtListener table, not across them
            '{{ kind }}' as item_kind,
            {{ descr }} as description,  -- noqa: AL03,RF04
            {{ amount }} as amount_code,
            {{ extra }} as detail,
            redacted = 't' as is_redacted
        from {{ source('courtlistener', table) }}
        {% if not loop.last %}union all{% endif %}
    {% endfor %}
)

select
    *,
    -- the guard skips the regex passes for the 93% of rows that are investments; they are false either way
    -- (false and x is false), and the else branch is the original expression, so null item_kind is unchanged
    case
        when item_kind = 'investment' then false
        else item_kind <> 'investment' and {{ mogov.is_garbled_text('description') }}
    end as is_garbled
from items
