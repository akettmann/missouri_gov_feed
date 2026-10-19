-- Money each official received from an industry or interest, per year: campaign contributions from
-- organizations, PACs and committees (individuals are left out: their employer is not their money) and
-- lobbyist gifts by the lobbyist's principal. The donor or principal name is classified by the whole-word
-- keywords in the interest_keywords seed ("Missouri Hospital Association PAC" -> health_care). A name can
-- match several industries ("Missouri Association of Insurance and Financial Advisors" -> insurance and
-- banking_finance) and then counts for each. Names with no keyword (opaque PAC acronyms) are left out.
-- match_confidence is the weakest official match among the rows rolled up.
with contributions as (
    select
        official_id,
        'contribution' as money_kind,
        cast(extract(year from transaction_date) as {{ dbt.type_int() }}) as money_year,
        coalesce(nullif(trim(counterparty_organization), ''), counterparty) as payer,
        amount,
        match_confidence
    from {{ ref('fct_campaign_finance') }}
    where direction = 'received' and lower(coalesce(counterparty_type, '')) <> 'individual'
),

gifts as (
    select
        official_id,
        'lobbyist gift' as money_kind,
        cast(expenditure_year as {{ dbt.type_int() }}) as money_year,
        lobbyist_principal as payer,
        amount,
        match_confidence
    from {{ ref('fct_lobbyist_gifts') }}
),

money as (
    select
        *,
        -- row identity: two identical contributions (same payer, amount, year) are both counted
        row_number() over (order by official_id, money_kind, money_year, payer, amount) as money_row,
        ' ' || {{ mogov.name_key('payer') }} || ' ' as payer_key
    from (
        select * from contributions
        union all
        select * from gifts
    ) as m
    where payer is not null and amount > 0
),

hits as (
    -- a name hitting two keywords of one industry ("hospital", "health") counts once
    select distinct
        m.money_row,
        k.industry
    from money as m
    inner join {{ ref('interest_keywords') }} as k
        on m.payer_key like '% ' || k.keyword || ' %'
),

classified as (
    select
        m.official_id,
        m.money_kind,
        m.money_year,
        m.payer,
        m.amount,
        m.match_confidence,
        h.industry
    from money as m
    inner join hits as h on m.money_row = h.money_row
)

select
    official_id,
    industry,
    money_kind,
    money_year,
    sum(amount) as total_amount,
    count(distinct payer) as payer_count,
    case when min(match_confidence) = 'high' and max(match_confidence) = 'high' then 'high' else 'medium' end
        as match_confidence
from classified
group by official_id, industry, money_kind, money_year
