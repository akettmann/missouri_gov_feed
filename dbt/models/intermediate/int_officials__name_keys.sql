-- Normalized name variants per current official, for matching sources that only carry names
-- (MEC committees, lobbyist reports, Wikidata labels, ratings). One row per (official, variant).
with base as (
    select
        official_id,
        level,
        office,
        full_name,
        given_name,
        family_name
    from {{ ref('int_officials__current') }}
),

variants as (
    select
        official_id,
        full_name as variant
    from base
    union
    select
        official_id,
        given_name || ' ' || family_name as variant
    from base
    union
    select
        b.official_id,
        n.alt_name as variant
    from base as b
    inner join {{ ref('stg_openstates__other_names') }} as n on b.official_id = n.openstates_id
    where n.alt_name not like '%,%'
)

select
    v.official_id,
    b.level,
    b.office,
    v.variant,
    {{ mogov.name_key('v.variant') }} as variant_key,
    {{ mogov.name_key('b.family_name') }} as family_key,
    {{ mogov.name_key(dbt.split_part('b.given_name', "' '", 1)) }} as given_key
from variants as v
inner join base as b on v.official_id = b.official_id
where v.variant is not null
