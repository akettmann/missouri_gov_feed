-- Voluntary disclosures (financial statements, conflict-of-interest statements, recusal notices...)
-- that officials published without being required to. No feed exists for these, so they're curated in
-- seeds/voluntary_disclosures.csv (one row per disclosure, with a source URL) and matched by name.
select
    k.official_id,
    s.disclosure_date,
    s.kind,
    s.description,
    s.source_url
from {{ ref('voluntary_disclosures') }} as s
inner join (
    select distinct
        official_id,
        variant_key
    from {{ ref('int_officials__name_keys') }}
) as k on {{ mogov.name_key('s.official_name') }} = k.variant_key
