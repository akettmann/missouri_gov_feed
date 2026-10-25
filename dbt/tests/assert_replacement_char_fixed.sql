-- mogov.fix_replacement_char on fixed examples, and no U+FFFD left in staged EPA FRS text; any row returned is
-- a failure.
with cases as (
    select
        'D�COR PLUS' as txt,
        'DÉCOR PLUS' as expected
    union all
    select
        'MARBLE D��COR INC' as txt,
        'MARBLE DÉCOR INC' as expected
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

left_over as (
    select facility_name as txt from {{ ref('stg_epa_frs__facilities') }}
    where facility_name like '%�%' or address like '%�%'
    union all
    select org_name as txt from {{ ref('stg_epa_frs__organizations') }}
    where org_name like '%�%'
)

select txt from wrong
union all
select txt from left_over
