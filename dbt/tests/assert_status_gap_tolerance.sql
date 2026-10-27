-- mogov.status_gap_exceeds on fixed inputs (#750); any row returned is a wrong verdict.
with cases as (
    select
        3 as total,
        1 as without_status,
        false as expected,
        '3-bill special session, one rejected fragment' as why
    union all
    select
        3 as total,
        2 as without_status,
        false as expected,
        'two of three still within the absolute tolerance' as why
    union all
    select
        3 as total,
        3 as without_status,
        true as expected,
        'whole session without status' as why
    union all
    select
        700 as total,
        70 as without_status,
        true as expected,
        'large session with a 10% gap' as why
    union all
    select
        700 as total,
        35 as without_status,
        false as expected,
        'large session at 5%' as why
    union all
    select
        700 as total,
        36 as without_status,
        true as expected,
        'large session just over 5%' as why
    union all
    select
        700 as total,
        3 as without_status,
        false as expected,
        'large session, 3 rows is well under 5%' as why
    union all
    select
        20 as total,
        3 as without_status,
        true as expected,
        'small session over the tolerance and over 5%' as why
)

select
    why,
    expected,
    {{ mogov.status_gap_exceeds('without_status', 'total') }} as actual
from cases
where {{ mogov.status_gap_exceeds('without_status', 'total') }} <> expected
