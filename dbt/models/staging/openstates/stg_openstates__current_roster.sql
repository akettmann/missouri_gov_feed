-- Open States flat current roster: adds Wikidata QIDs, which the YAML usually lacks.
select
    id as openstates_id,
    name as full_name,
    current_party,
    current_district,
    current_chamber,
    nullif(wikidata, '') as wikidata_qid,
    nullif(biography, '') as biography
from {{ source('openstates', 'current_csv') }}
