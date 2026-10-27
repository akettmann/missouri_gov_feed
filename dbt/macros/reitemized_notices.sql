{#- Contributions with the 24-hour notices that a later full report itemizes again removed (#156, #542).
    A gift of $5,000+ is first reported on a "24 Hour ..." notice and then listed again, as a line of its own, in the
    committee's next full report (8 Day Before, 30 Day After, Quarterly, ...). Both lines carry the same committee, date
    and amount, so the notice line is dropped. Only an equal date counts: a full report that dates the gift differently
    from the notice is not recognised, and both lines stay. Two matching tiers:

    1. Same donor. Rows sharing a key (committee, date, amount, donor) are numbered separately among the notices and
       among the full-report lines (by record_id), and the nth notice is dropped only if the nth full-report line
       exists, so a donor who gave the same amount twice in a day keeps both gifts when both appear in full reports and
       a notice with no matching full-report line (no later report, a different amount, date or donor) is kept. The
       donor is compared by name_key (case, punctuation and runs of spaces ignored).
    2. Same donor, spelled differently (#542). Among the lines tier 1 left over, a committee, date and amount with
       exactly ONE leftover notice and exactly ONE leftover full-report line (a donor-less line counts, so it blocks the
       match) is a pair when both lines name the same city and state and the donor names are loose_name_key twins, or
       within a couple of letters of each other (typos: "Lathrop GPM" / "Lanthrop GPM") on names of 10+ characters
       with the same digits ("LIUNA Local 110 PAC Fund" is not "LIUNA Local 100 PAC Fund"), and only when every word
       that differs between the two names is 5+ letters long in both ("Citizens for Ann Smith" is not "Citizens for
       Anne Smith", #735; see name_typo_match). With two or more leftover
       lines on either side it is unknowable who gave what, so every notice is kept.

    3. Abbreviations and added words (#557, #634). The same tier also pairs names where, word by word, one is a prefix of the
       other ("deVries and Assoc" / "DeVries and Associates", "Alliance ... Technical Ed" / "... Education") and the
       longer name has up to two more words at the end ("Committee to Elect Jamie Burger" / "... Burger HD"). The
       first word must be equal ("Ed Smith" is not "Edward Smith"), both names need two words, and the digits must match.
       A word that is only the start of another counts only when the longer one is an organisation word from the macro
       is_org_word_prefix (see name_words_match): person surnames never pair this way.
       Because that is a statement about two names, not about the count of lines, tiers 2 and 3 also run when the
       committee/date/amount has several leftover lines: a notice is dropped when it has exactly ONE name-compatible
       full-report line and that line has exactly ONE name-compatible notice, and no leftover line of the group lacks
       a donor name. Two compatible lines on either side keep every notice.

    A name whose loose key is empty (only stop words, legal forms and single letters: "A B", "The Co") is never matched
    in tiers 2 and 3 (#634): two such names would otherwise compare equal.

    Rows missing a committee, date, amount or donor are never matched in tier 1, and a row without a city and state
    never in tier 2. rel is a relation with record_id, mec_committee_id, contributor_name, contributor_city,
    contributor_state, amount, contribution_date and report.
    Applies to both MEC feeds: the TAP mirror and the direct export. -#}

{#- A donor name as a looser match key than name_key: "MO"/"Missouri" alike, stop words ("and", "of", "the"), legal-form
    words ("LLC", "Inc") and single letters (middle initials) dropped. "James B Nutter" and "James Nutter" give
    "james nutter"; "Democratic Federal Campaign Committee of St. Louis City PAC" and the same without "of" are equal.
    The padding spaces let each word be matched whole; the pass runs twice because adjacent words share a space. -#}
{% macro loose_name_key(expr) -%}
    {%- set words = " (and|of|the|inc|incorporated|llc|co|corp|company|ltd|[a-z]) " -%}
    {%- set padded = "replace(' ' || " ~ mogov.name_key(expr) ~ " || ' ', ' mo ', ' missouri ')" -%}
    trim({{ mogov.regex_replace_all(
        mogov.regex_replace_all(mogov.regex_replace_all(padded, words, ' '), words, ' '),
        ' +', ' '
    ) }})
{%- endmacro %}

{#- Organisation words that may be abbreviated or truncated in donor names (#634), for name_words_match: the longer word of
    a prefix pair must be one of these. Person surnames are deliberately absent, so "John Hill" / "John Hillhouse" and
    "Smith Alex" / "Smith Alexandra" never pair. Chosen from the words that really occur abbreviated in MEC donor names
    (October 2026). It is a macro list rather than a seed because dbt unit tests cannot run a model that refs a seed
    they do not mock, and every dedupe test would have to repeat the list. word is the longer word and prefix the
    shorter, both column names or expressions. A prefix needs 3+ letters, except 2 for Ed / Education. -#}
{% macro is_org_word_prefix(word, prefix) -%}
    (
        (
            length({{ prefix }}) >= 3
            and {{ word }} in (
                'accountants', 'administration', 'administrative', 'administrators', 'advisors', 'american',
                'anesthesiologists', 'anesthesiology', 'anesthetists', 'architects', 'architectural',
                'associate', 'associated', 'associates', 'association', 'associations', 'attorneys',
                'bankers', 'benevolent', 'builders', 'cattlemens', 'centers', 'chiropractors', 'commission',
                'commissioners', 'committee', 'committees', 'communications', 'community', 'construction',
                'constructors', 'consulting', 'contractors', 'convenience', 'cooperative', 'cooperatives',
                'corporation', 'corporations', 'corrections', 'council', 'democrat', 'democratic',
                'democrats', 'dermatological', 'development', 'district', 'districts', 'drivers', 'electric',
                'electrical', 'elevators', 'employees', 'engineering', 'engineers', 'enterprises', 'farms',
                'federal', 'federation', 'financial', 'firefighters', 'fitters', 'foods', 'glassworkers',
                'government', 'growers', 'healthcare', 'holdings', 'homes', 'hospital', 'hospitals',
                'independent', 'industries', 'insurance', 'international', 'investments', 'laborers',
                'legislative', 'local', 'locals', 'machinists', 'maintenance', 'management', 'marketers',
                'medical', 'metals', 'motors', 'municipal', 'national', 'officers', 'organization',
                'petroleum', 'pipefitters', 'plasterers', 'police', 'political', 'professional', 'realtors',
                'regional', 'rehabilitation', 'representative', 'republican', 'republicans', 'services',
                'society', 'solutions', 'state', 'states', 'stores', 'systems', 'teachers', 'technical',
                'telecommunication', 'telecommunications', 'trades', 'transportation', 'troopers', 'union',
                'voluntary', 'wholesale', 'wholesalers', 'workers'
            )
        )
        or (length({{ prefix }}) >= 2 and {{ word }} in ('education', 'educational'))
    )
{%- endmacro %}

{#- True when two loose_name_keys are the same name abbreviated or with words added (#557): at least two words in the
    shorter name, the first word equal, each later word of the shorter equal to or a prefix of the same-position word
    of the other, and at most two extra words on the longer. A word that is only a prefix of the other word counts
    only when the LONGER word is an organisation word listed in the macro is_org_word_prefix ("Assoc" / "Associates",
    "Ins" / "Insurance") and the prefix has 3+ letters, 2 for Ed / Education (#634). Surnames are not
    listed, so "John Hill" / "John Hillhouse", "Smith Alex" / "Smith Alexandra" and "Committee to Elect John Smith" /
    "... Smithson" stay unpaired, and words of 1-2 letters (except "Ed" for education) and Roman numerals ("Holding III"
    / "Holdings II") must be equal. Equal words and extra trailing words always count.
    Compares up to 8 words; digits are compared by the caller.
    n_a, n_b are the word counts of a, b (columns or expressions). -#}
{% macro name_words_match(a, b, n_a, n_b) -%}
    (
        least({{ n_a }}, {{ n_b }}) between 2 and 8
        and abs({{ n_a }} - {{ n_b }}) <= 2
        {%- for i in range(1, 9) %}
        {%- set wa = dbt.split_part(a, "' '", i) %}
        {%- set wb = dbt.split_part(b, "' '", i) %}
        and (
            least({{ n_a }}, {{ n_b }}) < {{ i }}
            or {{ wa }} = {{ wb }}
            {%- if i > 1 %}
            or (
                {{ wa }} like {{ wb }} || '%'
                and {{ mogov.is_org_word_prefix(wa, wb) }}
            )
            or (
                {{ wb }} like {{ wa }} || '%'
                and {{ mogov.is_org_word_prefix(wb, wa) }}
            )
            {%- endif %}
        )
        {%- endfor %}
    )
{%- endmacro %}

{#- True when two loose_name_keys differ by a typo (#542, #735): both names 10+ characters, at most two edits and at
    most one edit per ten characters (the digits are compared by the caller). A name is not a typo of another when the
    edit changes a short word: "Ann Smith" / "Anne Smith", "Joan" / "John" are two people, so every word that differs
    between the names (compared by position) must be 5+ letters in both names. "Lathrop GPM" / "Lanthrop GPM" and
    "Fran Froelich" / "Fran Froehlich" still pair. Compares up to 12 words; a longer name never pairs this way.
    Names with different word counts never pair through this tier (a missing word has length 0).
    n_a, n_b are the word counts of a, b (columns or expressions). -#}
{% macro name_typo_match(a, b, n_a, n_b) -%}
    (
        length({{ a }}) >= 10
        and length({{ b }}) >= 10
        and {{ mogov.edit_distance(a, b) }} <= 2
        and 10 * {{ mogov.edit_distance(a, b) }} <= greatest(length({{ a }}), length({{ b }}))
        and greatest({{ n_a }}, {{ n_b }}) <= 12
        {%- for i in range(1, 13) %}
        {%- set wa = "coalesce(" ~ dbt.split_part(a, "' '", i) ~ ", '')" %}
        {%- set wb = "coalesce(" ~ dbt.split_part(b, "' '", i) ~ ", '')" %}
        and (
            {{ wa }} = {{ wb }}
            or (length({{ wa }}) >= 5 and length({{ wb }}) >= 5)
        )
        {%- endfor %}
    )
{%- endmacro %}

{% macro drop_reitemized_notices(rel) -%}
with

keyed as (
    select
        record_id,
        upper(trim(mec_committee_id)) as match_committee_id,
        contribution_date as match_date,
        amount as match_amount,
        nullif({{ mogov.name_key('contributor_name') }}, '') as match_donor,
        nullif(upper(trim(contributor_city)), '') as match_city,
        nullif(upper(trim(contributor_state)), '') as match_state,
        coalesce(lower(report) like '%24 hour%', false) as is_notice
    from {{ rel }}
    where mec_committee_id is not null and contribution_date is not null and amount is not null
),

ranked as (
    select
        *,
        row_number() over (
            partition by match_committee_id, match_date, match_amount, match_donor, is_notice
            order by record_id
        ) as match_rank
    from keyed
    where match_donor is not null
),

exact_pairs as (
    select
        notice.record_id as notice_id,
        full_report.record_id as full_report_id
    from ranked as notice
    inner join ranked as full_report
        on
            notice.match_committee_id = full_report.match_committee_id
            and notice.match_date = full_report.match_date
            and notice.match_amount = full_report.match_amount
            and notice.match_donor = full_report.match_donor
            and notice.match_rank = full_report.match_rank
    where notice.is_notice and not full_report.is_notice
),

leftover as (
    select
        *,
        sum(case when match_donor is null then 1 else 0 end) over (
            partition by match_committee_id, match_date, match_amount
        ) as nameless_left
    from keyed
    where
        record_id not in (select notice_id from exact_pairs)
        and record_id not in (select full_report_id from exact_pairs)
),

similar_candidates as (
    select
        notice.record_id as notice_id,
        full_report.record_id as full_report_id,
        notice.nameless_left,
        {{ mogov.loose_name_key('notice.match_donor') }} as notice_loose,
        {{ mogov.loose_name_key('full_report.match_donor') }} as full_report_loose
    from leftover as notice
    inner join leftover as full_report
        on
            notice.match_committee_id = full_report.match_committee_id
            and notice.match_date = full_report.match_date
            and notice.match_amount = full_report.match_amount
            and notice.match_city = full_report.match_city
            and notice.match_state = full_report.match_state
    where
        notice.is_notice
        and not full_report.is_notice
        and notice.match_donor is not null
        and full_report.match_donor is not null
),

word_counts as (
    select
        *,
        length(notice_loose) - length(replace(notice_loose, ' ', '')) + 1 as notice_words,
        length(full_report_loose) - length(replace(full_report_loose, ' ', '')) + 1 as full_report_words
    from similar_candidates
),

compatible as (
    select
        *,
        count(*) over (partition by notice_id) as full_reports_for_notice,
        count(*) over (partition by full_report_id) as notices_for_full_report
    from word_counts
    where
        notice_loose <> ''
        and full_report_loose <> ''
        and (
            notice_loose = full_report_loose
            or (
                {{ mogov.regex_replace_all('notice_loose', '[^0-9]', '') }}
                = {{ mogov.regex_replace_all('full_report_loose', '[^0-9]', '') }}
                and (
                    {{ mogov.name_typo_match('notice_loose', 'full_report_loose', 'notice_words', 'full_report_words') }}
                    or {{ mogov.name_words_match('notice_loose', 'full_report_loose', 'notice_words', 'full_report_words') }}
                )
        )
        )
),

reitemized as (
    select notice_id as record_id from exact_pairs
    union
    select notice_id
    from compatible
    where full_reports_for_notice = 1 and notices_for_full_report = 1 and nameless_left = 0
)

select c.*
from {{ rel }} as c
where not exists (select 1 from reitemized as r where r.record_id = c.record_id)
{%- endmacro %}
