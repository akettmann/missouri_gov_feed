-- Sanity check (#449): every House roll call that survives staging has at least half of the listed members voting.
-- A recorded vote needs a quorum (82 of 163) and the fewest voters on any real roll call so far is 83 (a quorum
-- call), so a survivor under half of the members is either a voting-board test record that slipped under the
-- drop threshold in stg_mo_house__rollcalls (a quarter) or a genuine call that failed to produce a quorum; add
-- the latter's URL to var house_rollcall_small_quorum_allowlist in dbt_project.yml.
{% set allowlist = var('house_rollcall_small_quorum_allowlist') %}
{% set quoted = allowlist | map('replace', "'", "''") | map('string') | join("', '") %}
select
    rollcall_url,
    session_code,
    vote_date,
    measure,
    members_voting,
    members_listed
from {{ ref('stg_mo_house__rollcalls') }}
where
    members_voting * 2 < members_listed
{{ "    and rollcall_url not in ('" ~ quoted ~ "')" if allowlist | length > 0 else "" }}
