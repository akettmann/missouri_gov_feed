-- Members of Congress who ever represented Missouri, with cross-system IDs.
with src as (
    select
        payload as p,
        true as is_current
    from {{ source('congress', 'legislators_current') }}
    union all
    select
        payload as p,
        false as is_current
    from {{ source('congress', 'legislators_historical') }}
),

last_term as (
    select
        {{ mogov.json_str('s.p', '$.id.bioguide') }} as bioguide_id,
        t.value as term,
        row_number() over (partition by {{ mogov.json_str('s.p', '$.id.bioguide') }} order by t.idx desc) as rn
    from src as s
    cross join lateral {{ mogov.json_elements('s.p', '$.terms') }} as t
)

select
    {{ mogov.json_str('s.p', '$.id.bioguide') }} as bioguide_id,
    coalesce(
        {{ mogov.json_str('s.p', '$.name.official_full') }},
        {{ mogov.json_str('s.p', '$.name.first') }} || ' ' || {{ mogov.json_str('s.p', '$.name.last') }}
    ) as full_name,
    {{ mogov.json_str('s.p', '$.name.first') }} as given_name,
    {{ mogov.json_str('s.p', '$.name.last') }} as family_name,
    {{ dbt.safe_cast(mogov.json_str('s.p', '$.bio.birthday'), 'date') }} as birth_date,
    {{ mogov.json_str('s.p', '$.bio.gender') }} as gender,
    {{ dbt.safe_cast(mogov.json_str('s.p', '$.id.icpsr'), dbt.type_int()) }} as icpsr,
    {{ mogov.json_str('s.p', '$.id.opensecrets') }} as opensecrets_id,
    {{ mogov.json_str('s.p', '$.id.votesmart') }} as votesmart_id,
    {{ mogov.json_str('s.p', '$.id.wikidata') }} as wikidata_qid,
    {{ mogov.json_str('s.p', '$.id.lis') }} as senate_lis_id,
    {{ mogov.json_str('s.p', '$.id.wikipedia') }} as wikipedia_title,
    {{ mogov.json_str('s.p', '$.id.ballotpedia') }} as ballotpedia_title,
    {{ mogov.normalize_party(mogov.json_str('lt.term', '$.party')) }} as party,
    {{ mogov.json_str('lt.term', '$.type') }} as latest_term_type,
    {{ mogov.json_str('lt.term', '$.state') }} as latest_term_state,
    {{ mogov.json_str('lt.term', '$.district') }} as latest_term_district,
    {{ dbt.safe_cast(mogov.json_str('lt.term', '$.start'), 'date') }} as latest_term_start,
    {{ dbt.safe_cast(mogov.json_str('lt.term', '$.end'), 'date') }} as latest_term_end,
    s.is_current,
    s.p
from src as s
left join last_term as lt on {{ mogov.json_str('s.p', '$.id.bioguide') }} = lt.bioguide_id and lt.rn = 1
