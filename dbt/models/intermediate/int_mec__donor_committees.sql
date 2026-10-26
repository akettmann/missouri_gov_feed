-- Name -> MECID crosswalk for committee donors. MEC records a committee-to-committee gift with the donor's
-- name only (the row's MECID is the receiving committee), so the donor's own MECID is found by matching that
-- name to the names committees file under (int_mec__committee_names), in tiers:
--   curated alias      a curated donor name -> MECID list (committee_donor_aliases seed), each alias checked
--                      against the committee's own filings, for acronym and shortened names no rule can expand
--                      ("HRCC", "AMECPAC", "MHA PAC", #33); each row cites its evidence. Tried first, but only
--                      counts when that committee was active that year
--   0 mecid in name    the filer typed the donor's MECID into the name ("... (MEC ID# C221962)") and it's a
--                      known committee; taken whatever its active years
--   1 same name        name_key: case ignored; punctuation and other non-alphanumeric characters turned
--                      into spaces; runs of spaces collapsed, not removed (#108)
--   2 normalized name  committee_key: abbreviations spelled out (MO, Assn, Cmte...), "the/of/for/inc" dropped
--   3 core name        committee_core_key: also without words like PAC, Political, Action, Committee, Fund,
--                      Account, at least 4 characters; also tried on the name outside parentheses, and against
--                      a filer's own parenthesized short name
--                      ("Carpenters Help in the Political Process (CHIPP)" -> CHIPP)
-- A candidate counts only if it was active within a year of the gift (first_active_year - 1 ..
-- last_active_year + 1). The lowest tier with an active candidate decides: one candidate -> matched, several
-- -> ambiguous (no MECID; the candidates are listed). Names that only match committees active in other years
-- are "not active that year" (usually an older or newer committee under the same name), the rest "no match"
-- (mostly federal and out-of-state PACs, which don't file with MEC). One-character names ("C", "~") are
-- placeholders (#31): "placeholder name", never matched.
-- match_confidence: high for curated aliases and tiers 0-1 (the alias was matched to the committee's own
-- filings, or the name is the committee's own), medium for the looser tiers; either way it rests on the name.
with donations as (
    select
        contributor_committee_name as donor_committee_name,
        contribution_year,
        sum(amount) as amount,
        count(*) as contribution_count
    from {{ ref('int_mec__contributions_received') }}
    where contributor_committee_name is not null
    group by contributor_committee_name, contribution_year
),

donor_names as (
    select distinct donor_committee_name
    from donations
    where {{ dbt.length("trim(donor_committee_name)") }} >= 2
),

donor_keys as (
    select
        donor_committee_name,
        -1 as match_tier,
        {{ mogov.name_key('donor_committee_name') }} as name_key
    from donor_names
    union all
    select
        donor_committee_name,
        0 as match_tier,
        {{ mogov.regex_extract('upper(donor_committee_name)', '(^|[^A-Z0-9])([AC][0-9]{6})([^0-9]|$)', 2) }}
            as name_key
    from donor_names
    union all
    select
        donor_committee_name,
        1 as match_tier,
        {{ mogov.name_key('donor_committee_name') }} as name_key
    from donor_names
    union all
    select
        donor_committee_name,
        2 as match_tier,
        {{ mogov.committee_key('donor_committee_name') }} as name_key
    from donor_names
    union all
    select
        donor_committee_name,
        3 as match_tier,
        {{ mogov.committee_core_key('donor_committee_name') }} as name_key
    from donor_names
    union all
    select
        donor_committee_name,
        3 as match_tier,
        {{ mogov.committee_core_key(mogov.outside_parens('donor_committee_name')) }} as name_key
    from donor_names
),

committee_years as (
    select
        mec_committee_id,
        min(first_active_year) as first_active_year,
        max(last_active_year) as last_active_year
    from {{ ref('int_mec__committee_names') }}
    group by mec_committee_id
),

filer_keys as (
    -- an alias naming a MECID absent from the committees (or a typo) joins nothing, so it can't make a link
    select
        a.mec_committee_id,
        c.first_active_year,
        c.last_active_year,
        -1 as match_tier,
        {{ mogov.name_key('a.alias') }} as name_key
    from {{ ref('committee_donor_aliases') }} as a
    inner join committee_years as c on a.mec_committee_id = c.mec_committee_id
    union all
    select distinct
        mec_committee_id,
        first_active_year,
        last_active_year,
        0 as match_tier,
        mec_committee_id as name_key
    from {{ ref('int_mec__committee_names') }}
    union all
    select
        mec_committee_id,
        first_active_year,
        last_active_year,
        1 as match_tier,
        {{ mogov.name_key('committee_name') }} as name_key
    from {{ ref('int_mec__committee_names') }}
    union all
    select
        mec_committee_id,
        first_active_year,
        last_active_year,
        2 as match_tier,
        {{ mogov.committee_key('committee_name') }} as name_key
    from {{ ref('int_mec__committee_names') }}
    union all
    select
        mec_committee_id,
        first_active_year,
        last_active_year,
        3 as match_tier,
        {{ mogov.committee_core_key('committee_name') }} as name_key
    from {{ ref('int_mec__committee_names') }}
    union all
    select
        mec_committee_id,
        first_active_year,
        last_active_year,
        3 as match_tier,
        {{ mogov.committee_core_key(mogov.outside_parens('committee_name')) }} as name_key
    from {{ ref('int_mec__committee_names') }}
    union all
    select
        mec_committee_id,
        first_active_year,
        last_active_year,
        3 as match_tier,
        {{ mogov.committee_core_key(mogov.inside_parens('committee_name')) }} as name_key
    from {{ ref('int_mec__committee_names') }}
),

candidates as (
    select distinct
        d.donor_committee_name,
        d.match_tier,
        f.mec_committee_id,
        f.first_active_year,
        f.last_active_year
    from donor_keys as d
    inner join filer_keys as f on d.match_tier = f.match_tier and d.name_key = f.name_key
    where d.name_key <> '' and (d.match_tier < 3 or {{ dbt.length("d.name_key") }} >= 4)
),

year_candidates as (
    select
        g.donor_committee_name,
        g.contribution_year,
        c.match_tier,
        c.mec_committee_id,
        case
            when c.match_tier = 0 then 1
            when g.contribution_year between c.first_active_year - 1 and c.last_active_year + 1 then 1
            else 0
        end as is_active
    from donations as g
    inner join candidates as c on g.donor_committee_name = c.donor_committee_name
),

active_ids as (
    select distinct
        donor_committee_name,
        contribution_year,
        match_tier,
        mec_committee_id
    from year_candidates
    where is_active = 1
),

deciding_tier as (
    select
        donor_committee_name,
        contribution_year,
        min(match_tier) as match_tier
    from active_ids
    group by donor_committee_name, contribution_year
),

decided as (
    select
        a.donor_committee_name,
        a.contribution_year,
        a.match_tier,
        count(*) as n_candidates,
        min(a.mec_committee_id) as first_candidate,
        {{ dbt.listagg('a.mec_committee_id', "', '", 'order by a.mec_committee_id') }} as candidate_mec_committee_ids
    from active_ids as a
    inner join deciding_tier as t
        on
            a.donor_committee_name = t.donor_committee_name
            and a.contribution_year = t.contribution_year
            and a.match_tier = t.match_tier
    group by a.donor_committee_name, a.contribution_year, a.match_tier
),

named as (
    select distinct
        donor_committee_name,
        contribution_year
    from year_candidates
)

select
    g.donor_committee_name,
    g.contribution_year,
    g.amount,
    g.contribution_count,
    case when d.n_candidates = 1 then d.first_candidate end as mec_committee_id,
    case
        when d.n_candidates = 1 then 'matched'
        when d.n_candidates > 1 then 'ambiguous'
        when n.donor_committee_name is not null then 'not active that year'
        when {{ dbt.length("trim(g.donor_committee_name)") }} < 2 then 'placeholder name'
        else 'no match'
    end as match_status,
    case d.match_tier
        when -1 then 'curated alias'
        when 0 then 'mecid in name'
        when 1 then 'same name'
        when 2 then 'normalized name'
        when 3 then 'core name'
    end as match_method,
    case when d.n_candidates = 1 then case when d.match_tier <= 1 then 'high' else 'medium' end end
        as match_confidence,
    coalesce(d.n_candidates, 0) as n_candidates,
    d.candidate_mec_committee_ids
from donations as g
left join decided as d
    on g.donor_committee_name = d.donor_committee_name and g.contribution_year = d.contribution_year
left join named as n
    on g.donor_committee_name = n.donor_committee_name and g.contribution_year = n.contribution_year
