-- Golden check of the real seed mo_vote_stage_rules (the unit tests mock it): each real House calendar item and
-- Senate journal sentence in the seed mo_vote_stage_examples gets exactly the stage and informal flag listed there.
-- Returns every mismatch; a new phrasing is a seed row, and a rule removed or reordered so that an example changes
-- stage fails here.
with examples as (
    select
        chamber,
        vote_description,
        measure,
        expected_stage,
        expected_informal,
        row_number() over (order by chamber, vote_description, measure) as vote_id
    from {{ ref('mo_vote_stage_examples') }}
),

actual as (
    {{ classify_vote_stage('examples') }}
)

select
    e.chamber,
    e.vote_description,
    e.measure,
    e.expected_stage,
    a.vote_stage as actual_stage,
    e.expected_informal,
    a.vote_informal as actual_informal
from examples as e
inner join actual as a on e.chamber = a.chamber and e.vote_id = a.vote_id
where e.expected_stage != a.vote_stage or e.expected_informal != a.vote_informal
