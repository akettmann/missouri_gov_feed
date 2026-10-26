-- Committee posts held per official and House session: the number of full committees served on and the number
-- of titles held on them (chair, vice-chair, co-chair, ranking minority member), counted from the House's own
-- lists. Subcommittees (including joint-committee subcommittees) are counted apart so a member who chairs three
-- subcommittees is not shown as chairing three committees. A count of titles, not a score. Grain: one row per
-- (official, session).
select
    official_id,
    session_code,
    session_year,
    cast(sum(case when is_subcommittee then 0 else 1 end) as {{ dbt.type_bigint() }}) as committees_held,
    cast(
        sum(case when not is_subcommittee and position_name = 'Chair' then 1 else 0 end)
        as {{ dbt.type_bigint() }}
    ) as chair_posts,
    cast(
        sum(case when not is_subcommittee and position_name = 'Vice-Chair' then 1 else 0 end)
        as {{ dbt.type_bigint() }}
    ) as vice_chair_posts,
    cast(
        sum(case when not is_subcommittee and position_name = 'Co-Chair' then 1 else 0 end)
        as {{ dbt.type_bigint() }}
    ) as co_chair_posts,
    cast(
        sum(case when not is_subcommittee and position_name = 'Ranking Minority Member' then 1 else 0 end)
        as {{ dbt.type_bigint() }}
    ) as ranking_posts,
    cast(
        sum(case when is_subcommittee and position_name = 'Chair' then 1 else 0 end)
        as {{ dbt.type_bigint() }}
    ) as subcommittee_chair_posts
from {{ ref('fct_committee_memberships') }}
group by official_id, session_code, session_year
