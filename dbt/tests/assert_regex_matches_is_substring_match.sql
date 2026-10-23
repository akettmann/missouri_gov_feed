-- mogov.regex_matches must mean "the pattern matches anywhere in the string" on every adapter (#69). Snowflake's
-- regexp_like is implicitly anchored, so the macro uses regexp_instr there; this pins the intended semantic on the
-- adapter we run, with cases where an anchored match would give a different answer.
-- Returns the cases whose result differs from the expected one, so the test fails if the semantic drifts.
with cases as (
    select
        'two chars vs one-char class' as case_name,
        {{ mogov.regex_matches("'ab'", '[A-Za-z0-9]') }} as actual,
        true as expected
    union all
    select
        'one char' as case_name,
        {{ mogov.regex_matches("'a'", '[A-Za-z0-9]') }} as actual,
        true as expected
    union all
    select
        'no alphanumerics' as case_name,
        {{ mogov.regex_matches("'~ ~'", '[A-Za-z0-9]') }} as actual,
        false as expected
    union all
    select
        'leading anchor at start' as case_name,
        {{ mogov.regex_matches("'79047860 VINCENT'", '^[0-9]{6,} ') }} as actual,
        true as expected
    union all
    select
        'leading anchor not at start' as case_name,
        {{ mogov.regex_matches("'x 79047860 VINCENT'", '^[0-9]{6,} ') }} as actual,
        false as expected
    union all
    select
        'explicit full anchors reject mixed' as case_name,
        {{ mogov.regex_matches("'a1'", '^[0-9]+$') }} as actual,
        false as expected
    union all
    select
        'case-sensitive' as case_name,
        {{ mogov.regex_matches("'Doe Law Firm'", 'law') }} as actual,
        false as expected
    union all
    select
        'alternation inside a longer string' as case_name,
        {{ mogov.regex_matches("'a lawyer here'", 'lawyer|attorney') }} as actual,
        true as expected
)

select
    case_name,
    actual,
    expected
from cases
where actual is distinct from expected
