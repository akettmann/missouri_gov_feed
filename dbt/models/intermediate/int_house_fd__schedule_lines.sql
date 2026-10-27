-- House disclosure PDF text, each line tagged with the schedule it falls under (the nearest preceding
-- "Schedule X:" header in the same document). Column-header rows, "None disclosed." and boilerplate drop out.
-- Entries the PDF wraps over several lines are joined back into one row (see "continuation" below): on the schedules
-- that feed commercial ties (C, E, F, J) so a wrapped tail never becomes a tie of its own (#599), and on A, B, D and H
-- so a wrapped entry is not counted as several disclosure items (#641).
-- PDFs from 2021 on extract their small-caps text with NUL characters; the words are restored first (#576).
{# a line whose first "$" is a low end with no high end ("... $250,001 -"), and one whose last "$" is
   ("... Interest $201 -") #}
{% set first_low_only = '^[^$]*\\$[0-9,]+ -( [^$0-9]|$)' %}
{% set last_low_only = '\\$[0-9,]+ -( [^$0-9]*)?$' %}
with lines as (
    select
        doc_id,
        document_url,
        has_text,
        page,
        line_no,
        {{ mogov.house_fd_restore_text('line_text') }} as line_text
    from {{ ref('stg_house_fd__pdf_lines') }}
),

sequenced as (
    select
        *,
        row_number() over (partition by doc_id order by page, line_no) as seq,
        case
            when
                lower(line_text) like 'schedule a:%' or lower(line_text) like 'schedule a and b%'
                -- 2021+ layout: "Schedule A Asset Class Details" / "Schedule A Investment Vehicle Details"
                or lower(line_text) like 'schedule a %details'
                then 'A: assets & unearned income'
            when lower(line_text) like 'schedule b:%' then 'B: transactions'
            when lower(line_text) like 'schedule c:%' then 'C: earned income'
            when lower(line_text) like 'schedule d:%' then 'D: liabilities'
            when lower(line_text) like 'schedule e:%' then 'E: positions'
            when lower(line_text) like 'schedule f:%' then 'F: agreements'
            when lower(line_text) like 'schedule g:%' then 'G: gifts'
            when lower(line_text) like 'schedule h:%' then 'H: travel'
            when lower(line_text) like 'schedule i:%' then 'I: charity in lieu of honoraria'
            when lower(line_text) like 'schedule j:%' then 'J: compensation over $5,000 from one source'
            -- the form's closing pages (exclusion questions, certification, signature) follow the last schedule;
            -- their lines belong to no schedule (the sentinel is dropped below)
            when
                lower(line_text) like 'exclusions of spouse%' or lower(line_text) like 'certification and signature%'
                then 'end of form'
            when
                lower(line_text) like '%transaction date%' or lower(line_text) like 'id owner asset%'
                then 'PTR: transactions'
        end as header_schedule
    from lines
    where has_text
),

tagged as (
    select
        s.*,
        max(case when s.header_schedule is not null then s.seq end)
            over (partition by s.doc_id order by s.seq rows between unbounded preceding and current row) as header_seq
    from sequenced as s
),

kept as (
    select
        t.doc_id,
        t.document_url,
        t.page,
        t.line_no,
        t.seq,
        h.header_schedule as schedule,
        t.line_text
    from tagged as t
    inner join tagged as h on t.doc_id = h.doc_id and t.header_seq = h.seq
    where
        t.header_schedule is null
        and h.header_schedule != 'end of form'
        and lower(t.line_text) not in ('none disclosed.', 'none disclosed')
        and lower(t.line_text) not like 'asset owner value%'
        and lower(t.line_text) not like 'type(s) $1,000?%'
        and lower(t.line_text) not like 'source type amount%'
        and lower(t.line_text) not like 'position name of organization%'
        and lower(t.line_text) not like 'source (name and address)%'
        and lower(t.line_text) not like '%for the complete list of asset type%'
        and lower(t.line_text) not like 'filing id #%'
        -- column-header spill of the 2021+ layouts (schedule F and others): would otherwise become ties
        and lower(t.line_text) not like 'date parties to terms%'
        -- column-header spill, each an exact line (the header cell wraps onto its own line); a real asset or
        -- position never reads like one of these (#599)
        and lower(t.line_text) not in (
            'filing',
            'yes no',
            'i p o',
            'i v d',
            'liability',
            'exp.',
            '$200?',
            '$1,000?',
            'date exp.',
            'date own exp.',
            'trip details inclusions',
            'type gains >',
            'type date gains >',
            'asset owner date tx. amount cap.',
            'owner creditor date incurred type amount of',
            'source activity date amount charity name',
            'source start end date itinerary days at lodging? food? family?',
            'source start end date itinerary days at own lodging? food? family?',
            'source start date end date itinerary days at own lodging? food? family?'
        )
        -- "Type(s) of Income, Current Year to Filing / Preceding Year" wrapped over lines: nothing but those words
        and not {{ mogov.regex_matches(
            'lower(t.line_text)',
            '^(type\\(s\\) )?(current|preceding|filing|year|to)( (current|preceding|filing|year|to))*$'
        ) }}
        -- the asset-type-code footnote repeated on every page of schedule A / B
        and lower(t.line_text) not like 'https://fd.house.gov/reference/asset-type-codes%'
        and lower(t.line_text) not like '* asset class details available at the bottom of this form%'
),

-- Continuation: on the schedules that feed commercial ties, a wrapped entry leaves its tail as a line of its own.
-- A line is the tail of the entry above (same schedule) when
--   * C: it carries no amount ("$..." or "N/A"): the first line holds the amounts, so a line without one (or a
--     "Comments:" line) belongs to the entry above;
--   * F: it does not start with the agreement's date (a year, optionally after a month): Date, Parties, Terms;
--   * C, E, F, J: it closes a parenthesis the entry above left open, or starts with one ("Name (Owensboro," then
--     "KY, US)"; "... Consulting services" then "(Jefferson City, MO, US)").
--   * A: it is nothing but income-type words ("Dividends", "Capital Gains,"), nothing but amounts (the high end of a
--     range wrapped under the low end) or form-checkbox glyphs ("gfedc"), or a ticker and asset-type code
--     ("(OANEX) [MF]", "[MF]");
--   * B: it carries no transaction type before an amount ("P $1,001 - ...", "S (partial) $..."): the 2021+ layout
--     puts the asset name on the line(s) after the account/date/amount line. A date alone does not make a line an
--     entry: bond names wrap with their maturity ("Rev 5% 07/01/2031 [GS] $100,000", "05/24/2028 [GS]");
--   * D: it carries no amount ("$..." or "N/A") and does not end on "Over" (an amount wrapped to the next line), or it
--     is nothing but amounts;
--   * A, B, D: the line above holds only the low end of its value range ("... $250,001 -", or "$500,001 - Dividends
--     $2,501 -" in the 2021+ layout) and this one has an amount but no range of its own: the high end, with the part of
--     the description that wrapped ("Road $500,000", "Merck & Company, Inc. (MRK) [ST] $1,000,000 $5,000");
--   * H: it carries no date (mm/dd/yyyy): the sponsor, itinerary and city names wrap around the line with the dates.
-- "Location:" / "Description:" / "Comments:" lines of B stay lines of their own (labelled attributes), and so do
-- those of A unless the rules above apply: a parenthesis the entry above left open ("(50% Inter") pulls the next
-- line in, "DESCRIPTION:" included (3 lines).
-- Other lines stay entries: pure wrapped tails with no such signal ("Government") cannot be told from an entry, and
-- neither can an asset name wrapped over two lines on A ("Fidelity Managed Income II III [HE]" / "Unit Cl I [HE]").
flagged as (
    select
        k.*,
        lag(k.schedule) over (partition by k.doc_id order by k.seq) as prev_schedule,
        lag(k.line_text) over (partition by k.doc_id order by k.seq) as prev_text,
        lag(k.line_text, 2) over (partition by k.doc_id order by k.seq) as prev2_text
    from kept as k
),

continued as (
    select
        f.*,
        coalesce(f.prev_schedule = f.schedule, false) and (
            (
                substr(f.schedule, 1, 1) in ('C', 'E', 'F', 'J', 'A', 'B', 'D', 'H') and (
                    length(f.prev_text) - length(replace(f.prev_text, '(', ''))
                    > length(f.prev_text) - length(replace(f.prev_text, ')', ''))
                    or length(f.line_text) - length(replace(f.line_text, ')', ''))
                    > length(f.line_text) - length(replace(f.line_text, '(', ''))
                    or f.line_text like '(%'
                )
            )
            or (
                substr(f.schedule, 1, 1) = 'C'
                and not {{ mogov.regex_matches('f.line_text', '\\$[0-9]|(^| )[Nn]/[Aa]( |$)') }}
            )
            or (
                substr(f.schedule, 1, 1) = 'F'
                and not {{ mogov.regex_matches(
                    'lower(f.line_text)',
                    '^((january|february|march|april|may|june|july|august|september|october|november|december) )?[0-9]{4}( |$)'
                ) }}
            )
            or (
                substr(f.schedule, 1, 1) = 'A'
                and {{ mogov.regex_matches(
                    'lower(f.line_text)',
                    '^((dividends|interest|capital gains|rent|royalties|tax-deferred|none)[, ]*)+$'
                    ~ '|^(\\$[0-9,.]+ ?)+$|^(gfedcb? ?)+$|^(\\([a-z0-9.]+\\) )?\\[[a-z]{2}\\]$'
                ) }}
            )
            or (
                substr(f.schedule, 1, 1) = 'B'
                and not {{ mogov.regex_matches('f.line_text', '(^| )(P|S|E)( \\([Pp]artial\\))? (\\$[0-9]|None)') }}
                and not {{ mogov.regex_matches('lower(f.line_text)', '^(location|description|comments):') }}
            )
            or (
                substr(f.schedule, 1, 1) = 'D'
                and (
                    not {{ mogov.regex_matches('f.line_text', '\\$[0-9]|(^| )[Nn]/[Aa]( |$)|(^| )Over$') }}
                    or {{ mogov.regex_matches('f.line_text', '^(\\$[0-9,.]+ ?)+$') }}
                )
            )
            or (
                substr(f.schedule, 1, 1) in ('A', 'B', 'D')
                and (
                    {{ mogov.regex_matches('f.prev_text', first_low_only) }}
                    -- the checkbox glyphs of the first line wrap onto a line of their own before the asset name
                    or (
                        {{ mogov.regex_matches('f.prev_text', '^(gfedcb? ?)+$') }}
                        and {{ mogov.regex_matches('f.prev2_text', first_low_only) }}
                    )
                )
                and {{ mogov.regex_matches('f.line_text', '\\$[0-9]') }}
                and not {{ mogov.regex_matches('f.line_text', '\\$[0-9,]+ -( |$)') }}
            )
            -- A: the value range is complete and the income range wrapped after its low end ("$15,001 - $50,000
            -- Interest $201 -" / "Clark Cnty WA Sch Dist $1,000"); the glyphs may sit between the two lines
            or (
                substr(f.schedule, 1, 1) = 'A'
                and (
                    {{ mogov.regex_matches('f.prev_text', last_low_only) }}
                    or (
                        {{ mogov.regex_matches('f.prev_text', '^(gfedcb? ?)+$') }}
                        and {{ mogov.regex_matches('f.prev2_text', last_low_only) }}
                    )
                )
                and {{ mogov.regex_matches('f.line_text', '\\$[0-9]') }}
                and not {{ mogov.regex_matches('f.line_text', '\\$[0-9,]+ -( |$)|Over \\$') }}
            )
            -- A: the value "Over" (the amount wrapped to the next line, with the asset name): "Equity Trust CO => Over
            -- None" / "Berkshire Hathaway Inc. New (BRK.B) $50,000,000"
            or (
                substr(f.schedule, 1, 1) = 'A'
                and {{ mogov.regex_matches('f.prev_text', '(^| )Over( None)?$') }}
                and not {{ mogov.regex_matches('lower(f.prev_text)', '^(location|description|comments):') }}
                and {{ mogov.regex_matches('f.line_text', '\\$[0-9]') }}
                and not {{ mogov.regex_matches('f.line_text', '\\$[0-9,]+ -( |$)') }}
            )
            or (
                substr(f.schedule, 1, 1) = 'H'
                and not {{ mogov.regex_matches('f.line_text', '[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}') }}
            )
        ) as is_continuation
    from flagged as f
),

entries as (
    select
        c.*,
        max(case when not c.is_continuation then c.seq end)
            over (partition by c.doc_id order by c.seq rows between unbounded preceding and current row) as entry_seq
    from continued as c
),

joined as (
    select
        e.doc_id,
        e.entry_seq,
        {{ dbt.listagg('e.line_text', "' '", 'order by e.seq') }} as line_text
    from entries as e
    group by e.doc_id, e.entry_seq
)

-- owner code and the amount's low end come from the entry's first line: a joined tail must not add or change them.
-- A range the PDF wrapped ("$250,001 -" / "Road $500,000", or "Over" / "$1,000,000") takes its high end from the tail.
-- Owner codes exist only on schedules with an owner column (A, B, D and the PTR): a "DC" in a travel itinerary
-- ("Washington, DC") is a city, not a dependent child (#702). On D the code opens the line.
select
    e.doc_id,
    e.document_url,
    e.page,
    e.line_no,
    e.seq,
    e.schedule,
    j.line_text,
    -- owner codes: SP spouse, DC dependent child, JT joint
    case
        when substr(e.schedule, 1, 1) in ('A', 'B', 'P')
            then {{ mogov.regex_extract('e.line_text', '(^| )(SP|DC|JT)( |$)', 2) }}
        when substr(e.schedule, 1, 1) = 'D'
            then {{ mogov.regex_extract('e.line_text', '^(SP|DC|JT)( |$)') }}
    end as owner_code,
    case
        when
            {{ mogov.regex_matches('e.line_text', first_low_only) }}
            -- "None" / "Undetermined" before the first "$": that is the asset's value and the "$" starts the income
            -- range
            and not {{ mogov.regex_matches('e.line_text', '^([^$]* )?(None|Undetermined) [^$]*\\$') }}
            and e.line_text != j.line_text
            then
                {{ mogov.regex_extract('e.line_text', '(\\$[0-9,]+)') }}
                || coalesce(
                    ' - ' || {{ mogov.regex_extract('substr(j.line_text, length(e.line_text) + 2)', '(\\$[0-9,]+)') }},
                    ''
                )
        -- "Over" with the amount on the next line ("Over" / "$1,000,000", or A's "Over None" / "... $50,000,000")
        when {{ mogov.regex_matches('e.line_text', '(^| )Over( None)?$') }} and e.line_text != j.line_text
            then 'Over ' || {{ mogov.regex_extract('substr(j.line_text, length(e.line_text) + 2)', '(\\$[0-9,]+)') }}
        else {{ mogov.regex_extract('e.line_text', '(\\$[0-9,]+( - \\$[0-9,]+)?|Over \\$[0-9,]+|None|Undetermined)') }}
    end as amount_range
from entries as e
inner join joined as j on e.doc_id = j.doc_id and e.seq = j.entry_seq
