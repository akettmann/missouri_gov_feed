-- State officials' contributions from individuals by contribution size, per election cycle, in the same bands
-- the FEC uses for federal candidates (fct_federal_donor_summary by_size), so state and federal views line
-- up. MEC itemizes contributions over $100 and reports smaller ones only as a total, so the smallest band
-- here counts itemized contributions of $100.01-$199.99 plus whatever smaller ones a committee chose to itemize.
-- match_confidence stays in the grain so the frontend can hide medium (name-only) matches.
with individual as (
    select
        official_id,
        match_confidence,
        amount,
        cast(extract(year from transaction_date) as {{ dbt.type_int() }}) as transaction_year
    from {{ ref('fct_campaign_finance') }}
    where
        direction = 'received'
        and level = 'state'
        and lower(counterparty_type) = 'individual'
        and amount > 0
),

banded as (
    select
        official_id,
        match_confidence,
        amount,
        transaction_year + mod(transaction_year, 2) as election_cycle,
        case
            when amount < 200 then 0
            when amount < 500 then 200
            when amount < 1000 then 500
            when amount < 2000 then 1000
            else 2000
        end as band_floor
    from individual
)

select
    official_id,
    cast(election_cycle as {{ dbt.type_int() }}) as election_cycle,
    cast(band_floor as {{ dbt.type_int() }}) as band_floor,
    match_confidence,
    cast(sum(amount) as {{ dbt.type_numeric() }}) as total_amount,
    cast(count(*) as {{ dbt.type_bigint() }}) as contribution_count
from banded
group by official_id, election_cycle, band_floor, match_confidence
