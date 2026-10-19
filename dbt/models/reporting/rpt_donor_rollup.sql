-- Money received by each official's campaign committees, rolled up by donor and year. The donor is the
-- counterparty's organization when the source names one (an individual's employer, a PAC's connected
-- organization), else the counterparty's own name. donor_class groups the sources' counterparty types
-- into PAC / individual / party / ... . match_confidence is kept in the grain so the frontend can flag or
-- hide medium matches. Individual federal donors are not itemized here (see fct_federal_donor_summary).
with received as (
    select
        official_id,
        level,
        source,
        source_url,
        match_confidence,
        amount,
        transaction_date,
        cast(extract(year from transaction_date) as {{ dbt.type_int() }}) as transaction_year,
        coalesce(nullif(trim(counterparty_organization), ''), nullif(trim(counterparty), ''), '(unnamed)')
            as donor_name,
        case
            when lower(counterparty_type) = 'individual' then 'individual'
            when lower(counterparty_type) like '%pac%' then 'pac'
            when lower(counterparty_type) like 'party%' then 'party'
            when counterparty_type in ('House', 'Senate', 'Presidential') then 'candidate committee'
            when lower(counterparty_type) = 'committee' then 'committee'
            when lower(counterparty_type) in ('corporation', 'organization') then 'business or organization'
            else 'other'
        end as donor_class
    from {{ ref('fct_campaign_finance') }}
    where direction = 'received'
)

select
    official_id,
    level,
    transaction_year,
    -- federal two-year cycles end in even years; state reports are annual but follow the same elections
    transaction_year + mod(transaction_year, 2) as election_cycle,
    donor_class,
    donor_name,
    match_confidence,
    source,
    source_url,
    sum(amount) as total_amount,
    count(*) as contribution_count,
    min(transaction_date) as first_date,
    max(transaction_date) as last_date
from received
group by
    official_id,
    level,
    transaction_year,
    donor_class,
    donor_name,
    match_confidence,
    source,
    source_url
