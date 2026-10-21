-- mogov.is_garbled_text on real AO-10 OCR text (CourtListener judicial disclosures); any row returned is a
-- misclassification.
with cases as (
    select
        '2200 =oK00 =o OL00 Es 0. B1=$1,000,001:$5,000,000 + P4=More than $50,000,000' as txt,
        true as expected
    union all
    select
        'SIE = RE' as txt,
        true as expected
    union all
    select
        'EE TTT ————' as txt,
        true as expected
    union all
    select
        '5. - Ie — ~~ Fe) 7 _ il — = [hi' as txt,
        true as expected
    union all
    select
        'i PRisliddeast Sh iL if - 2 AE 1H iil J I D4 w corm Py ro —' as txt,
        true as expected
    union all
    select
        '1. Income Gain Codes: A S1LO00 of less B=$1,001 - $2,500 D=$5,001 - $14,000 E=$15,001 - $50,000' as txt,
        true as expected
    union all
    select
        'State of Missoun - Salary' as txt,
        false as expected
    union all
    select
        'Co-Trustee - Trust #1' as txt,
        false as expected
    union all
    select
        'Member ——————————————— - Federalist Society' as txt,
        false as expected
    union all
    select
        'BOARD OF DIRECTORS - COMPREHENSIVE YOUTH SERVICES' as txt,
        false as expected
    union all
    select
        'David C. Prant: Trip to Antigua on Yacht, 1-14-18 to 1-21-18' as txt,
        false as expected
    union all
    select
        'Wages Virginia Commonwealth University = Assistant Professor' as txt,
        false as expected
    union all
    select
        'SoFi - Loan' as txt,
        false as expected
    union all
    select
        'AT&T' as txt,
        false as expected
    union all
    select
        '<- AT&T' as txt,
        false as expected
    union all
    select
        '' as txt,
        false as expected
    union all
    select
        cast(null as {{ dbt.type_string() }}) as txt,
        false as expected
)

select
    txt,
    expected,
    {{ mogov.is_garbled_text('txt') }} as actual
from cases
where {{ mogov.is_garbled_text('txt') }} <> expected
