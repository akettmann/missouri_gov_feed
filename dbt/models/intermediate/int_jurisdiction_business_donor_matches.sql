-- One row per (official, facility, donor) tying a donor organization to an EPA-regulated facility in the area of a
-- district-elected official it gave to: the matching behind fct_jurisdiction_businesses (one row per facility)
-- and fct_jurisdiction_business_donors (one row per donor and filing page). See fct_jurisdiction_businesses for
-- what counts as a match. donor_key is the normalized organization name (company_key); donor_name is the name as filed.
with areas as (
    select
        o.official_id,
        f.registry_id
    from {{ ref('fct_official_districts') }} as o
    inner join {{ ref('fct_district_facilities') }} as f on o.district_id = f.district_id
    where
        o.relation in ('elected from', 'mayor of')
        and not f.is_government
    group by o.official_id, f.registry_id
),

donors as (
    select
        official_id,
        {{ mogov.company_key("coalesce(nullif(trim(counterparty_organization), ''), counterparty)") }} as donor_key,
        -- CR/LF would split a line of the `<url> <donor>` text the frontend writes into the site CSV and the
        -- per-official JSON, so they become spaces here (#268). Everything else is kept as filed: a ";" or a
        -- "," in a name stays, since the donors are rows, not a delimited string (#350, #370)
        trim(
            replace(
                replace(
                    replace(
                        min(coalesce(nullif(trim(counterparty_organization), ''), counterparty)),
                        {{ mogov.chr(13) }} || {{ mogov.chr(10) }},
                        ' '
                    ),
                    {{ mogov.chr(13) }}, ' '
                ),
                {{ mogov.chr(10) }}, ' '
            )
        ) as donor_name,
        sum(amount) as amount,
        count(*) as n_contributions,
        min(extract(year from transaction_date)) as first_year,
        max(extract(year from transaction_date)) as last_year,
        -- 1 when any of the money was tied to the official by a medium (name-only) match
        max(case when match_confidence = 'medium' then 1 else 0 end) as is_medium
    from {{ ref('fct_campaign_finance') }}
    where
        direction = 'received'
        and lower(coalesce(counterparty_type, '')) <> 'individual'
        and amount > 0
    group by
        official_id,
        {{ mogov.company_key("coalesce(nullif(trim(counterparty_organization), ''), counterparty)") }}
),

-- The padded name key is computed once per name, then joined to the brand keywords with a plain `like`. Computing
-- name_key inside the ON clause re-ran its regexes for every (name x keyword) pair (#883)
donor_name_keys as (
    select
        official_id,
        donor_key,
        ' ' || {{ mogov.name_key('donor_name') }} || ' ' as padded_name
    from donors
),

donor_brands as (
    select distinct
        d.official_id,
        d.donor_key,
        b.brand
    from donor_name_keys as d
    inner join {{ ref('company_brands') }} as b
        on d.padded_name like '% ' || b.keyword || ' %'
),

-- A facility matches a brand when any of its facility, owner or parent names does: the union of the three
-- padded keys followed by `distinct` is the same set as the OR of the three conditions
facility_name_keys as (
    select
        registry_id,
        ' ' || {{ mogov.name_key("coalesce(facility_name, '')") }} || ' ' as padded_name
    from {{ ref('int_epa_frs__facilities') }}
    union
    select
        registry_id,
        ' ' || {{ mogov.name_key("coalesce(owner_name, '')") }} || ' ' as padded_name
    from {{ ref('int_epa_frs__facilities') }}
    union
    select
        registry_id,
        ' ' || {{ mogov.name_key("coalesce(parent_company_name, '')") }} || ' ' as padded_name
    from {{ ref('int_epa_frs__facilities') }}
),

facility_brands as (
    select distinct
        n.registry_id,
        b.brand
    from facility_name_keys as n
    inner join {{ ref('company_brands') }} as b
        on n.padded_name like '% ' || b.keyword || ' %'
),

-- One row per (facility, company key) over the facility, owner and parent names, so the by-name match below is an
-- equality join. Joining on `donor_key in (facility_key, owner_key, parent_company_key)` can't use a hash key: it
-- paired every donor of an official with every facility in their area (55M rows, ~5GB) before filtering (#818)
facility_keys as (
    select
        registry_id,
        facility_key as company_key
    from {{ ref('int_epa_frs__facilities') }}
    union
    select
        registry_id,
        owner_key as company_key
    from {{ ref('int_epa_frs__facilities') }}
    union
    select
        registry_id,
        parent_company_key as company_key
    from {{ ref('int_epa_frs__facilities') }}
),

matched_donors as (
    select
        a.official_id,
        a.registry_id,
        d.donor_key,
        1 as by_name
    from areas as a
    inner join facility_keys as k on a.registry_id = k.registry_id
    inner join donors as d
        on
            a.official_id = d.official_id
            and k.company_key = d.donor_key
    where {{ dbt.length('d.donor_key') }} >= 4

    union all

    select
        a.official_id,
        a.registry_id,
        db.donor_key,
        0 as by_name
    from areas as a
    inner join facility_brands as fb on a.registry_id = fb.registry_id
    inner join donor_brands as db on a.official_id = db.official_id and fb.brand = db.brand
),

matches as (
    -- one row per (official, facility, donor) before summing, so a donor matched both ways counts once
    select
        m.official_id,
        m.registry_id,
        m.donor_key,
        max(m.by_name) as by_name,
        min(d.donor_name) as donor_name,
        min(d.amount) as amount,
        min(d.n_contributions) as n_contributions,
        min(d.first_year) as first_year,
        min(d.last_year) as last_year,
        min(d.is_medium) as is_medium
    from matched_donors as m
    inner join donors as d on m.official_id = d.official_id and m.donor_key = d.donor_key
    group by m.official_id, m.registry_id, m.donor_key
)

select
    official_id,
    registry_id,
    donor_key,
    by_name,
    donor_name,
    amount,
    n_contributions,
    first_year,
    last_year,
    is_medium
from matches
