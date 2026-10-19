-- Shor-McCarty state legislator ideology (Missouri only). np_score: one career ideal point,
-- negative = liberal, positive = conservative, comparable across states and chambers.
-- The wide per-year chamber/district columns are unpivoted to find each legislator's last seat.
{% set years = range(1993, 2023) %}
with mo as (
    select * from {{ source('shor_mccarty', 'scores') }}
    where st = 'MO'
),

seats as (
    {% for y in years %}
        select
            u_id,
            {{ y }} as year,
            'upper' as chamber,
            sdistrict{{ y }} as district
        from mo
        where senate{{ y }} = '1.0' or senate{{ y }} = '1'
        union all
        select
            u_id,
            {{ y }} as year,
            'lower' as chamber,
            hdistrict{{ y }} as district
        from mo
        where house{{ y }} = '1.0' or house{{ y }} = '1'
        {% if not loop.last %}union all{% endif %}
    {% endfor %}
),

last_seat as (
    select
        u_id,
        year,
        chamber,
        district,
        row_number() over (partition by u_id order by year desc, chamber asc) as rn,
        min(year) over (partition by u_id) as first_year
    from seats
)

select
    m.u_id as shor_mccarty_id,
    m.name as name_last_first,
    trim({{ dbt.split_part('m.name', "','", 1) }}) as family_name,
    trim({{ dbt.split_part('m.name', "','", 2) }}) as given_name,
    m.party,
    {{ dbt.safe_cast('m.np_score', dbt.type_float()) }} as np_score,
    s.first_year,
    s.year as last_year,
    s.chamber as last_chamber,
    {{ dbt.safe_cast(dbt.safe_cast('s.district', dbt.type_float()), dbt.type_int()) }} as last_district
from mo as m
left join last_seat as s on m.u_id = s.u_id and s.rn = 1
