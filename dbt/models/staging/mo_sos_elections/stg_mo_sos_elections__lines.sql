-- Missouri Secretary of State official returns: one row per printed PDF line (as the loader split it), with the
-- election, the contest sequence number within the PDF, and the cells of candidate rows. Numbers are parsed here.
-- The 2014-2020 PDFs print a ballot measure's choices as "<measure> Ballot Issue Yes: 499,581 Yes: 50.1%" and
-- "No: 497,091 No: 49.9%". The loader lands these unsplit (kind 'other'); they are recognised here and given the same
-- kind and cells ("Yes Votes" / "No Votes" in the party cell) as the 2012 and 2022+ measures.
with raw_lines as (
    select
        record_key as line_key,
        {{ mogov.json_str('payload', '$.election_key') }} as election_key,
        {{ mogov.json_str('payload', '$.election_type') }} as election_type,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.election_date'), 'date') }} as election_date,
        {{ mogov.json_str('payload', '$.pdf_url') }} as pdf_url,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.page'), dbt.type_int()) }} as page,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.line'), dbt.type_int()) }} as line,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.contest_seq'), dbt.type_int()) }} as contest_seq,
        {{ mogov.json_str('payload', '$.kind') }} as raw_kind,
        {{ mogov.json_str('payload', '$.text') }} as line_text,
        nullif(trim({{ mogov.json_str('payload', '$.cells.name') }}), '') as raw_name,
        nullif(trim({{ mogov.json_str('payload', '$.cells.party') }}), '') as raw_party,
        {{ mogov.json_str('payload', '$.cells.votes') }} as raw_votes,
        {{ mogov.json_str('payload', '$.cells.pct') }} as raw_pct
    from {{ source('mo_sos_elections', 'rows') }}
),

flagged as (
    select
        *,
        raw_kind = 'other'
        and {{ mogov.regex_matches('line_text', '^.+ Ballot Issue Yes: [0-9,]+ Yes: [0-9.]+%$') }} as is_old_yes,
        raw_kind = 'other'
        and {{ mogov.regex_matches('line_text', '^No: [0-9,]+ No: [0-9.]+%$') }} as is_old_no
    from raw_lines
)

select
    line_key,
    election_key,
    election_type,
    election_date,
    pdf_url,
    page,
    line,
    contest_seq,
    case when is_old_yes or is_old_no then 'candidate' else raw_kind end as kind,
    line_text,
    case
        when is_old_yes then trim({{ mogov.regex_extract('line_text', '^(.+) Ballot Issue Yes: ') }})
        else raw_name
    end as cell_name,
    case
        when is_old_yes then 'Yes Votes'
        when is_old_no then 'No Votes'
        else raw_party
    end as cell_party,
    {{ dbt.safe_cast(
        dbt.replace(
            "coalesce("
            ~ mogov.regex_extract('line_text', '^.+ Ballot Issue Yes: ([0-9,]+) Yes: ') ~ ", "
            ~ mogov.regex_extract('line_text', '^No: ([0-9,]+) No: ') ~ ", "
            ~ "raw_votes)",
            "','", "''"),
        dbt.type_bigint()) }} as cell_votes,
    {{ dbt.safe_cast(
        dbt.replace(
            "coalesce("
            ~ mogov.regex_extract('line_text', ' Yes: ([0-9.]+)%$') ~ ", "
            ~ mogov.regex_extract('line_text', ' No: ([0-9.]+)%$') ~ ", "
            ~ "raw_pct)",
            "'%'", "''"),
        'decimal(5, 1)') }} as cell_pct
from flagged
