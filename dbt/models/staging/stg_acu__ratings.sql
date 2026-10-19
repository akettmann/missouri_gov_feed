-- American Conservative Union (CPAC) yearly ratings of Missouri legislators (0-100; higher = votes more
-- often with ACU's positions), with the chamber/district they held that year.
with people as (
    select
        record_key as acu_id,
        {{ mogov.json_str('payload', '$.firstName') }} as given_name,
        {{ mogov.json_str('payload', '$.lastName') }} as family_name,
        payload
    from {{ source('raw', 'acu_ratings') }}
),

ratings as (
    select
        p.acu_id,
        {{ dbt.safe_cast(mogov.json_str('r.value', '$.year'), dbt.type_int()) }} as year,
        {{ dbt.safe_cast(mogov.json_str('r.value', '$.rating'), dbt.type_float()) }} as rating
    from people as p
    cross join lateral {{ mogov.json_elements('p.payload', '$.acuRatings') }} as r
),

history as (
    select
        p.acu_id,
        {{ dbt.safe_cast(mogov.json_str('h.value', '$.year'), dbt.type_int()) }} as year,
        {{ mogov.json_str('h.value', '$.chamber') }} as chamber,
        {{ mogov.normalize_party(mogov.json_str('h.value', '$.party')) }} as party,
        {{ dbt.safe_cast(mogov.json_str('h.value', '$.district'), dbt.type_int()) }} as district
    from people as p
    cross join lateral {{ mogov.json_elements('p.payload', '$.history') }} as h
)

select
    p.acu_id,
    p.given_name,
    p.family_name,
    r.year,
    r.rating,
    h.chamber,
    h.party,
    h.district
from people as p
inner join ratings as r on p.acu_id = r.acu_id
left join history as h on r.acu_id = h.acu_id and r.year = h.year
