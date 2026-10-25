-- mogov.fix_replacement_char on fixed examples, the alternative-name repairs applied, and no U+FFFD left in staged EPA
-- FRS text; any row returned is a failure.
with cases as (
    select
        'D�COR PLUS' as txt,
        'DCOR PLUS' as expected
    union all
    select
        'MARBLE D��COR INC' as txt,
        'MARBLE DCOR INC' as expected
    union all
    select
        '17123 HWY 60�' as txt,
        '17123 HWY 60' as expected
    union all
    select
        'CENTER� FEDERAL' as txt,
        'CENTER FEDERAL' as expected
    union all
    select
        'PLAIN NAME' as txt,
        'PLAIN NAME' as expected
),

wrong as (
    select txt
    from cases
    where {{ mogov.fix_replacement_char('txt') }} != expected
),

-- the alternative-name repair (the seed is empty) must reach staging; without it these would read "DCOR PLUS"
expected_names as (
    select
        '110014353788' as registry_id,
        'DECOR PLUS' as expected
    union all
    select
        '110071193073' as registry_id,
        'MARBLE DECOR INC' as expected
),

not_corrected as (
    select f.facility_name as txt
    from {{ ref('stg_epa_frs__facilities') }} as f
    inner join expected_names as e on f.registry_id = e.registry_id
    where f.facility_name != e.expected
    union all
    select o.org_name as txt
    from {{ ref('stg_epa_frs__organizations') }} as o
    where o.registry_id = '110014353788' and o.program_id = 'MOP000508036' and o.org_name != 'DECOR PLUS'
),

left_over as (
    select facility_name as txt from {{ ref('stg_epa_frs__facilities') }}
    where facility_name like '%�%' or address like '%�%'
    union all
    select org_name as txt from {{ ref('stg_epa_frs__organizations') }}
    where org_name like '%�%'
)

select txt from wrong
union all
select txt from not_corrected
union all
select txt from left_over
