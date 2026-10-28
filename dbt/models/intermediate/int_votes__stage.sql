-- The stage of every Missouri roll call (#804): perfection, third reading, consent calendar, conference, veto
-- override, ... derived from the House calendar item / Senate journal sentence by the rules in the seed
-- mo_vote_stage_rules (macro classify_vote_stage). Grain: one row per (chamber, vote_id). Federal roll calls are
-- not here (Voteview carries its own vote_question).
with roll_calls as (
    select distinct
        chamber,
        vote_id,
        calendar_item as vote_description,
        measure
    from {{ ref('int_mo_house__votes') }}
    union
    select distinct
        chamber,
        vote_id,
        context as vote_description,
        measure
    from {{ ref('int_mo_senate__votes') }}
)

{{ classify_vote_stage('roll_calls') }}
