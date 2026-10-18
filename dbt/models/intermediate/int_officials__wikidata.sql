-- Wikidata QID per official: from roster cross-references when present, else a unique exact name match
-- against living Missouri officeholders on Wikidata.
with known as (
    select
        o.official_id,
        coalesce(c.wikidata_qid, r.wikidata_qid) as qid,
        'roster id' as match_method
    from {{ ref('int_officials__current') }} as o
    left join {{ ref('stg_congress__legislators') }} as c on o.bioguide_id = c.bioguide_id
    left join {{ ref('stg_openstates__current_roster') }} as r on o.openstates_id = r.openstates_id
    where coalesce(c.wikidata_qid, r.wikidata_qid) is not null
),

by_name as (
    select
        k.official_id,
        max(w.qid) as qid,
        'exact name (Missouri officeholder)' as match_method
    from {{ ref('int_officials__name_keys') }} as k
    inner join {{ ref('stg_wikidata__officeholders') }} as w on k.variant_key = {{ mogov.name_key('w.label') }}
    where k.official_id not in (select kn.official_id from known as kn)
    group by k.official_id
    having count(distinct w.qid) = 1
)

select * from known
union all
select * from by_name
