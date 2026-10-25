-- Who among the officials is or was a judge or lawyer, and the evidence. Drives case-history lookups.
--   judge      currently a judge (state or federal roster)
--   lawyer     bio mentions practicing law / attorney / prosecutor / J.D., or Wikidata occupation says so
with sitting_judges as (
    select
        official_id,
        'judge' as legal_role,
        office_title as evidence,
        'judicial roster' as source
    from {{ ref('int_officials__current') }}
    where
        office like 'mo_%judge%'
        or office in ('mo_supreme_court', 'mo_court_of_appeals', 'us_district_court', 'us_court_of_appeals')
),

bio_mentions as (
    select
        official_id,
        case
            when lower(bio_text) like '%judge%' and lower(bio_text) like '%elected%judge%' then 'judge'
            when lower(bio_text) like '%prosecut%' then 'lawyer'
            else 'lawyer'
        end as legal_role,
        {{ mogov.regex_extract(
            'bio_text',
            '([^.]*(attorney|J\\.D\\.|law degree|practic(ed|es|ing) law|law firm|prosecut|public defender|bar of|admitted to the bar|judge)[^.]*\\.)'
        ) }} as evidence,
        source
    from {{ ref('int_officials__bios') }}
    where {{ mogov.regex_matches(
        'lower(bio_text)',
        'attorney|j\\.d\\.|juris doctor|law degree|practic(ed|es|ing) law|law firm|prosecut|public defender|admitted to the (missouri )?bar|judge'
    ) }}
),

wikidata as (
    select
        q.official_id,
        case when lower(f.value) like '%judge%' or lower(f.value) like '%jurist%' then 'judge' else 'lawyer' end
            as legal_role,
        f.fact_kind || ': ' || f.value as evidence,
        'Wikidata' as source
    from {{ ref('int_officials__wikidata') }} as q
    inner join {{ ref('stg_wikidata__facts') }} as f on q.qid = f.qid
    where
        (
            f.fact_kind = 'occupation'
            and {{ mogov.regex_matches('lower(f.value)', 'lawyer|attorney|jurist|judge|prosecutor|barrister') }}
        )
        or (
            f.fact_kind = 'position held'
            and {{ mogov.regex_matches('lower(f.value)', 'judge|attorney general|prosecut|justice') }}
        )
)

select * from sitting_judges
union all
select * from bio_mentions
where evidence is not null
union all
select * from wikidata
