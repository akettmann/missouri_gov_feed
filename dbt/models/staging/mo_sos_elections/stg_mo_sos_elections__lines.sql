-- Missouri Secretary of State official returns: one row per printed PDF line (as the loader split it), with the
-- election, the contest sequence number within the PDF, and the cells of candidate rows. Numbers are parsed here.
select
    record_key as line_key,
    {{ mogov.json_str('payload', '$.election_key') }} as election_key,
    {{ mogov.json_str('payload', '$.election_type') }} as election_type,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.election_date'), 'date') }} as election_date,
    {{ mogov.json_str('payload', '$.pdf_url') }} as pdf_url,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.page'), dbt.type_int()) }} as page,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.line'), dbt.type_int()) }} as line,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.contest_seq'), dbt.type_int()) }} as contest_seq,
    {{ mogov.json_str('payload', '$.kind') }} as kind,
    {{ mogov.json_str('payload', '$.text') }} as line_text,
    nullif(trim({{ mogov.json_str('payload', '$.cells.name') }}), '') as cell_name,
    nullif(trim({{ mogov.json_str('payload', '$.cells.party') }}), '') as cell_party,
    {{ dbt.safe_cast(dbt.replace(mogov.json_str('payload', '$.cells.votes'), "','", "''"), dbt.type_bigint()) }}
        as cell_votes,
    {{ dbt.safe_cast(dbt.replace(mogov.json_str('payload', '$.cells.pct'), "'%'", "''"), 'decimal(5, 1)') }} as cell_pct
from {{ source('mo_sos_elections', 'rows') }}
