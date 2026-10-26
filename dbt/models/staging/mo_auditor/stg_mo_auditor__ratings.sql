-- The performance rating read from each audit report's PDF, one row per report that was read. `rating` is the
-- word of the sentence "In the areas audited, the overall performance of this entity was <rating>." as
-- the Auditor spells it (null when the PDF has no such sentence: performance audits, special reports). The
-- rating covers only the areas audited. rating_sentence, pdf_url and page are the provenance.
with src as (
    select
        {{ mogov.json_str('payload', '$.report_number') }} as report_number,
        {{ mogov.json_str('payload', '$.source_kind') }} as source_kind,
        {{ mogov.json_str('payload', '$.pdf_url') }} as pdf_url,
        {{ mogov.json_str('payload', '$.status') }} as extraction_status,
        {{ mogov.json_str('payload', '$.rating_sentence') }} as rating_sentence,
        {{ mogov.json_str('payload', '$.rating_word') }} as rating_word,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.page'), dbt.type_int()) }} as page,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.n_sentences'), dbt.type_int()) }} as n_rating_sentences
    from {{ source('mo_auditor', 'ratings') }}
)

select
    report_number,
    source_kind,
    pdf_url,
    extraction_status,
    rating_sentence,
    {{ mogov.title_case('lower(rating_word)') }} as rating,
    page,
    n_rating_sentences
from src
