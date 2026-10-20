-- Employers of the individuals who gave to each official ("employees of X gave $Y"), from the employer field
-- the reports carry for individual contributors (fct_campaign_finance.counterparty_organization). Rows with no
-- employer are left out, and so are placeholder answers that name no employer (retired, self-employed, none,
-- n/a, "information requested", ...: the donor_employer_placeholders seed) and bare occupations (attorney,
-- owner). Names are compared lower-cased and trimmed but not otherwise merged, so spelling variants
-- ("diamond pet food", "diamond pet foods") stay apart. Federal individual donors aren't itemized in
-- fct_campaign_finance, so this is state money.
with individual as (
    select
        official_id,
        lower(trim(counterparty_organization)) as employer_key,
        trim(counterparty_organization) as employer,
        lower(trim(counterparty)) as donor_key,
        amount,
        match_confidence,
        source_url,
        cast(extract(year from transaction_date) as {{ dbt.type_int() }}) as transaction_year
    from {{ ref('fct_campaign_finance') }}
    where
        direction = 'received'
        and lower(counterparty_type) = 'individual'
        and nullif(trim(counterparty_organization), '') is not null
)

select
    i.official_id,
    -- one display spelling per employer key (the alphabetically first as filed)
    cast(min(i.employer) as {{ dbt.type_string() }}) as employer,
    i.match_confidence,
    cast(count(distinct i.donor_key) as {{ dbt.type_bigint() }}) as donor_count,
    cast(count(*) as {{ dbt.type_bigint() }}) as contribution_count,
    cast(sum(i.amount) as {{ dbt.type_numeric() }}) as total_amount,
    cast(min(i.transaction_year) as {{ dbt.type_int() }}) as first_year,
    cast(max(i.transaction_year) as {{ dbt.type_int() }}) as last_year,
    cast(min(i.source_url) as {{ dbt.type_string() }}) as source_url
from individual as i
left join {{ ref('donor_employer_placeholders') }} as p on i.employer_key = p.placeholder
where
    p.placeholder is null
    -- 'self-employed attorney', 'self / owner': not an employer; 'selfridge' is one, so match the separator
    and i.employer_key not like 'self-%'
    and i.employer_key not like 'self %'
    and i.employer_key not like 'self/%'
group by i.official_id, i.employer_key, i.match_confidence
