-- One row per action in a Senate bill's history on senate.mo.gov (both chambers, enrollment and the governor),
-- newest first as served: action_index 0 is the top row. The wording is the Senate's own ("S First Read",
-- "Second Read and Referred S Government Efficiency Committee"), not the House's. journal_ref names the journal
-- page that records the action (it can name both chambers, "H2291 / S1216") and journal_url links the PDF page.
-- session_code is the House's code for the session (seed mo_senate_session_codes), null for a session with no
-- seed row. action_seq is the chronological order within the bill, 1 = the first action (the reverse of the served
-- order). chamber is who acted, read from the wording: G when it names the Governor ("Signed by Governor"), H or S
-- when exactly one of the standalone tokens H / S appears ("H Third Read and Passed", "Referred H Budget",
-- "Second Read and Referred S Appropriations Committee", "SS S offered"), else null ("Perfected", "Signed by House
-- Speaker", or an action naming both).
-- session_year is read from `list_year` when the loader wrote one, else from the served `year` key (they agree).
{%- set year_expr -%}
coalesce(
    {{ mogov.json_str('payload', '$.list_year') }},
    {{ mogov.json_str('payload', '$.year') }}
)
{%- endset %}
with src as (
    select
        {{ dbt.safe_cast(year_expr, dbt.type_int()) }} as session_year,
        {{ mogov.json_str('payload', '$.session_type') }} as session_type,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.bill_id'), dbt.type_int()) }} as bill_id,
        {{ mogov.json_str('payload', '$.bill') }} as bill,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.action_index'), dbt.type_int()) }} as action_index,
        {{ mogov.json_str('payload', '$.action_date') }} as action_date_text,
        {{ mogov.json_str('payload', '$.action') }} as action,
        {{ mogov.json_str('payload', '$.journal_ref') }} as journal_ref,
        {{ mogov.json_str('payload', '$.journal_url') }} as journal_url
    from {{ source('mo_senate', 'bill_actions') }}
)

select
    src.session_year,
    src.session_type,
    codes.house_session_code as session_code,
    src.bill_id,
    src.bill,
    src.action_index,
    row_number() over (
        partition by src.session_year, src.session_type, src.bill_id
        order by src.action_index desc
    ) as action_seq,
    {{ mogov.parse_date('src.action_date_text', '%m/%d/%Y') }} as action_date,
    src.action_date_text,
    src.action,
    case
        when src.action like '%Governor%' then 'G'
        when (' ' || src.action || ' ') like '% H %' and (' ' || src.action || ' ') not like '% S %' then 'H'
        when (' ' || src.action || ' ') like '% S %' and (' ' || src.action || ' ') not like '% H %' then 'S'
    end as chamber,
    src.journal_ref,
    src.journal_url
from src
left join {{ ref('mo_senate_session_codes') }} as codes
    on src.session_year = codes.session_year and src.session_type = codes.session_type
