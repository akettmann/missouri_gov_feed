-- mogov.classify_outcome on real CourtListener disposition wordings; any row returned is a misclassification.
with cases as (
    select
        'AFFIRMED' as disposition,
        'affirmed' as expected
    union all
    select
        'Affirmed and Remanded with Instructions' as disposition,
        'affirmed' as expected
    union all
    select
        'REVERSED AND REMANDED FOR FURTHER PROCEEDINGS' as disposition,
        'reversed and remanded' as expected
    union all
    select
        'Reverse and remand in part and affirm in part' as disposition,
        'affirmed in part, reversed in part' as expected
    union all
    select
        'AFFIRMED AS TO POINTS I-IV, AND REVERSED AS TO POINT V' as disposition,
        'affirmed in part, reversed in part' as expected
    union all
    select
        'VACATED AND REMANDED' as disposition,
        'vacated' as expected
    union all
    select
        'APPEAL DISMISSED; CAUSE REMANDED' as disposition,
        'dismissed' as expected
    union all
    select
        'REMANDED WITH DIRECTIONS' as disposition,
        'remanded' as expected
    union all
    select
        'PRELIMINARY WRIT MADE PERMANENT' as disposition,
        'writ granted' as expected
    union all
    select
        'PRELIMINARY ORDER IN MANDAMUS MADE PERMANENT' as disposition,
        'writ granted' as expected
    union all
    select
        'PRELIMINARY WRIT QUASHED' as disposition,
        'writ denied' as expected
    union all
    select
        'CAUSE RETRANSFERRED' as disposition,
        'transferred' as expected
    union all
    select
        'SUSPENDED' as disposition,
        'other' as expected
    union all
    select
        '  ' as disposition,
        cast(null as {{ dbt.type_string() }}) as expected
)

select
    disposition,
    expected,
    {{ mogov.classify_outcome('disposition') }} as actual
from cases
where coalesce({{ mogov.classify_outcome('disposition') }}, '-') <> coalesce(expected, '-')
