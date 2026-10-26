-- Missouri Secretary of State official returns: the "Total Votes" line printed under each contest (or under each
-- judge of a retention block, matched by subcontest_seq), kept to reconcile the candidate rows against.
with ordered as (
    select
        election_key,
        contest_seq,
        kind,
        {{ mogov.regex_extract('line_text', '^Total Votes ([0-9,]+)$') }} as vote_digits,
        pdf_url,
        page,
        line,
        cast(sum(case when cell_party = 'Yes Votes' then 1 else 0 end) over (
            partition by election_key, contest_seq
            order by page, line
            rows between unbounded preceding and current row
        ) as {{ dbt.type_int() }}) as subcontest_seq
    from {{ ref('stg_mo_sos_elections__lines') }}
    where kind in ('candidate', 'total')
)

select
    election_key,
    contest_seq,
    subcontest_seq,
    {{ dbt.safe_cast(dbt.replace('vote_digits', "','", "''"), dbt.type_bigint()) }} as printed_total_votes,
    pdf_url,
    page,
    line
from ordered
where kind = 'total'
