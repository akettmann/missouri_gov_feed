-- The donors behind fct_jurisdiction_businesses, one row per (official, facility, donor, filing page): which
-- donor organizations gave to the official and were tied to the facility, and each page their gifts to the
-- official are filed on (#370). A donor with no filing-page url keeps one row with a null source_url.
-- Matching is int_jurisdiction_business_donor_matches.
with donor_urls as (
    -- every distinct filing page a donor's money to the official is filed on: a donor that gave to an MEC and
    -- an FEC committee, or to two FEC committees, keeps one row each instead of min() picking one (#248)
    select distinct
        official_id,
        {{ mogov.company_key("coalesce(nullif(trim(counterparty_organization), ''), counterparty)") }} as donor_key,
        source_url
    from {{ ref('fct_campaign_finance') }}
    where
        direction = 'received'
        and lower(coalesce(counterparty_type, '')) <> 'individual'
        and amount > 0
        and source_url is not null
)

select distinct
    m.official_id,
    m.registry_id,
    m.donor_name,
    u.source_url
from {{ ref('int_jurisdiction_business_donor_matches') }} as m
left join donor_urls as u on m.official_id = u.official_id and m.donor_key = u.donor_key
