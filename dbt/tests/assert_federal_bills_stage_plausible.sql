-- Sanity checks on int_federal_bills__stage. Returns a row per problem. Per Congress: no more than 1,000 laws (recent
-- Congresses enact 270-350) and no more than 50 vetoes (Biden 13, Trump 10 in a term); a Congress that has finished
-- (the 118th, 2023-2025) has at least 100 laws (it had 274); an override cannot be complete without a veto.
-- (A bill whose actions say it became law but that is not on the laws list is a warning, in
-- assert_federal_bills_became_law_on_laws_list.sql: GovInfo can add the action before it updates the list.)
with per_congress as (
    select
        congress,
        sum(case when stage = 'became_law' then 1 else 0 end) as laws,
        sum(case when vetoed_date is not null then 1 else 0 end) as vetoes
    from {{ ref('int_federal_bills__stage') }}
    group by congress
)

select
    cast(congress as varchar) as problem_key,
    'too many laws or vetoes' as problem
from per_congress
where laws > 1000 or vetoes > 50

union all

select
    cast(congress as varchar) as problem_key,
    'finished Congress with fewer than 100 laws' as problem
from per_congress
where congress <= 118 and laws < 100

union all

select
    bill_id as problem_key,
    'veto overridden without a veto' as problem
from {{ ref('int_federal_bills__stage') }}
where president_outcome = 'veto_overridden' and vetoed_date is null
