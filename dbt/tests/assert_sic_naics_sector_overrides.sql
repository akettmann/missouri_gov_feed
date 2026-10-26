-- Spot checks on the real sic_naics_sectors seed (the unit test mocks it): SIC codes whose major group maps to
-- a different sector than the Census 1987 SIC to NAICS concordance gives them, so the longer row must win.
-- Returns the codes that resolve to the wrong sector.
with expected (sic_code, naics_prefix) as (
    values
    ('4922', '48'), -- natural gas transmission: pipeline transportation, not utilities (49 -> 22)
    ('4923', '48'),
    ('4952', '22'), -- sewerage stays a utility
    ('6798', '53'), -- REITs: real estate, not finance (67 -> 52)
    ('7331', '54'), -- direct mail advertising; the rest of 73 is administrative support (56)
    ('7336', '54'), -- commercial art and graphic design
    ('7383', '51'), -- news syndicates
    ('7384', '81'), -- photofinishing laboratories
    ('6552', '23'), -- land subdividers: construction (237210), not real estate
    ('7514', '53'), -- passenger car rental; the rest of 75 is repair (81)
    ('4953', '56')
),

resolved as (
    select
        e.sic_code,
        e.naics_prefix as expected_prefix,
        m.naics_prefix as seed_prefix,
        row_number() over (partition by e.sic_code order by length(m.sic_prefix) desc) as rn
    from expected as e
    left join {{ ref('sic_naics_sectors') }} as m on left(e.sic_code, length(m.sic_prefix)) = m.sic_prefix
)

select
    sic_code,
    expected_prefix,
    seed_prefix
from resolved
where rn = 1 and seed_prefix is distinct from expected_prefix
