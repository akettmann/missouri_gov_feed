-- Lobbyist gifts per official, rolled up by the principal (the client the lobbyist reports for), category
-- and year. Categories are upper-cased: the TAP mirror and MEC spell them differently ("Gift" vs "GIFT").
-- match_confidence is kept in the grain so the frontend can flag or hide medium matches.
select
    official_id,
    expenditure_year,
    coalesce(nullif(trim(lobbyist_principal), ''), '(not reported)') as lobbyist_principal,
    upper(coalesce(expenditure_category, 'OTHER')) as expenditure_category,
    match_confidence,
    source,
    sum(amount) as total_amount,
    count(*) as gift_count,
    count(distinct lobbyist_name) as lobbyist_count,
    min(expenditure_date) as first_date,
    max(expenditure_date) as last_date,
    -- MEC has no per-report permalink; this is its public lobbyist expenditure search
    'https://www.mec.mo.gov/MEC/Lobbying/LobExpSearch.aspx' as source_url
from {{ ref('fct_lobbyist_gifts') }}
group by
    official_id,
    expenditure_year,
    coalesce(nullif(trim(lobbyist_principal), ''), '(not reported)'),
    upper(coalesce(expenditure_category, 'OTHER')),
    match_confidence,
    source
