{#
  Classify Missouri roll calls by stage (#804). `relation` is the name of a CTE (or relation) with one row per
  roll call and the columns chamber, vote_id, vote_description (the House calendar item or the Senate journal
  sentence) and measure. The result has chamber, vote_id, vote_stage and vote_informal.

  vote_stage: the first rule (lowest priority number within the chamber) in the seed mo_vote_stage_rules whose
  description_pattern and measure_pattern (SQL LIKE, ignoring case; a missing text counts as empty) both match.
  A roll call no rule matches is `unknown`, so a new phrasing is never guessed into a stage: add a seed row.
  vote_informal: the House calendar item ends in the informal-calendar marker (INFORMAL or INF); always false for
  the Senate, whose journal has no such marker. Federal roll calls are not classified here.
#}
{% macro classify_vote_stage(relation) -%}
select
    c.chamber,
    c.vote_id,
    coalesce(m.stage, 'unknown') as vote_stage,
    c.chamber = 'state_house' and (
        lower(coalesce(c.vote_description, '')) like '%informal%'
        or lower(coalesce(c.vote_description, '')) like '%-inf'
        or lower(coalesce(c.vote_description, '')) like '% inf'
    ) as vote_informal
from {{ relation }} as c
left join (
    select
        x.chamber,
        x.vote_id,
        r.stage,
        row_number() over (partition by x.chamber, x.vote_id order by r.priority) as rn
    from {{ relation }} as x
    inner join {{ ref('mo_vote_stage_rules') }} as r
        on
            x.chamber = r.chamber
            and lower(coalesce(x.vote_description, '')) like lower(r.description_pattern)
            and lower(coalesce(x.measure, '')) like lower(r.measure_pattern)
) as m
    on c.chamber = m.chamber and c.vote_id = m.vote_id and m.rn = 1
{%- endmacro %}
