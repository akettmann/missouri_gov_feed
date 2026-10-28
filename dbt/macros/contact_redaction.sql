{# Separator classes (#711 round 2). Real comments use Unicode dashes (en dash U+2013 in "751–6662") and no-break
   spaces, so the patterns accept them as separators INSTEAD OF rewriting the text: only the redacted span changes,
   the rest of the comment keeps its characters. Dashes: U+2010-U+2015 (hyphen, non-breaking hyphen, figure, en and
   em dash, horizontal bar), U+2212 minus, and the ASCII hyphen last. Spaces: space, U+00A0, U+202F. #}
{% macro sep_dash() -%}[‐‑‒–—―−-]{%- endmacro %}
{% macro sep_any() -%}[   .‐‑‒–—―−-]{%- endmacro %}
{# Gap between the digit groups of a 10-digit number (#751): optional space, optional dash or dot, optional space, so
   "573 - 751 - 1167", "573 -751- 1167" and "(573) - 751-1167" read as one number. A character class only (no
   group), so the replacement group numbers below do not move. #}
{% macro sep_gap() -%}[   ]?[   .‐‑‒–—―−-]?[   ]?{%- endmacro %}
{% macro sep_nodot() -%}[   ‐‑‒–—―−-]{%- endmacro %}

{# Redact contact strings from free text, keeping the rest of the sentence. This project keeps citizens' email
   addresses and phone numbers in raw and join keys only (never in models or exports), so staging replaces just
   the address or number with a marker instead of dropping the whole text. Patterns are POSIX ERE (see
   compat/strings.sql). A public official's office phone is redacted too: the pattern cannot tell whose it is.
   Email: local part, @, a dotted host; a sentence-ending dot after the host stays outside the match.
   Phone (contact_phone_pattern, used for redaction; the guard adds the broader guard_phone_pattern): a 10-digit number whose
   separators (space, dot, dash) may be absent, optional parentheses on the area code, a leading +1, or 1 followed
   by a separator (or 11 plain digits), and a trailing extension (ext. 12, x12); or the 7-digit Capitol office
   form 751-6662, DASH ONLY (#711: real data has no space-separated 7-digit phone, and a space form also matches
   bill lists such as "SB 123 4567" and "100 1000 dollars"; a spaced or dotted 7-digit number is left to the
   warn-level has_phone_like_digits check). Both sit between non-digits, so ranges (2001-2013), dates and amounts
   are not caught. A bare 1 before the area code needs a separator, so "751-6662 751-1167 751-1168" cannot read
   "-1167 751-1168" as a 1-prefixed number.
   Spaces around the dashes of a 10-digit number are accepted ("573 - 751 - 1167", #751). The dotted 7-digit form
   "751.6662" is NOT redacted: "RSMo 135.1150" has the same shape, so it stays a warn-level check (#751). #}
{# Groups: 1 = the character before, 6 = the character after (both kept on replacement). #}
{% macro contact_phone_pattern() -%}
    (^|[^0-9])(([+]1{{ mogov.sep_any() }}?|1{{ mogov.sep_any() }})?[(]?[0-9]{3}[)]?{{ mogov.sep_gap() }}[0-9]{3}{{ mogov.sep_gap() }}[0-9]{4}|1[0-9]{10}|1[(][0-9]{3}[)]{{ mogov.sep_gap() }}[0-9]{3}{{ mogov.sep_gap() }}[0-9]{4}|[0-9]{3}{{ mogov.sep_dash() }}[0-9]{4})([ ]?(ext[.]?|EXT[.]?|Ext[.]?|x|X)[ ]?[0-9]{1,5})?([^0-9]|$)
{%- endmacro %}

{% macro redact_contact(expr) -%}
    {%- set no_email = mogov.regex_replace_all(expr, '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+([.][A-Za-z0-9-]+)+', '[email removed]') -%}
    {#- Twice: the character after one number is the character before the next ("751-6662 or 751-1167"), so one pass
        takes every other number of a list and the second takes the rest, however long the list. -#}
    {{ mogov.regex_replace_all(
        mogov.regex_replace_all(no_email, mogov.contact_phone_pattern(), '\\1[phone removed]\\6'),
        mogov.contact_phone_pattern(),
        '\\1[phone removed]\\6'
    ) }}
{%- endmacro %}

{# Broad pattern for the build-failing guard (#711), run on text that is ALREADY redacted: 10 digits with any
   separators and an optional +1 / 1 prefix (with or without a separator), or a 7-digit number with a space or dash
   ("751 6662"). Looser than contact_phone_pattern on purpose: redaction stays narrow so it does not mangle bill
   lists, but anything that still looks like a phone after redaction must fail the build. Bill numbers are masked
   first (guard_bill_mask_pattern), so "SB 123 4567" or "HCR 12 3456" pass; "100 1000 dollars" fails loudly. #}
{% macro guard_phone_pattern() -%}
    (^|[^0-9])(([+]?1{{ mogov.sep_any() }}?)?[(]?[0-9]{3}[)]?{{ mogov.sep_gap() }}[0-9]{3}{{ mogov.sep_gap() }}[0-9]{4}|[0-9]{3}{{ mogov.sep_nodot() }}[0-9]{4}|[0-9]{3}/[0-9]{4})([^0-9]|$)
{%- endmacro %}

{% macro guard_bill_mask_pattern() -%}
    (^|[^A-Za-z])[HS][CJ]?[BR][ ]?[0-9]+
{%- endmacro %}

{# SQL boolean: the (redacted) text still holds an email address, a phone number or a stray @. For build-failing
   guards: the redaction pattern, then the broader guard pattern over the text with bill numbers masked. #}
{% macro has_contact_string(expr) -%}
    (
        {{ expr }} like '%@%'
        or {{ mogov.regex_matches(expr, mogov.contact_phone_pattern()) }}
        or {{ mogov.regex_matches(
            mogov.regex_replace_all(expr, mogov.guard_bill_mask_pattern(), '\\1BILL'), mogov.guard_phone_pattern()
        ) }}
    )
{%- endmacro %}

{# Broader, warn-level check (#711): digit runs that look like a phone but that contact_phone_pattern deliberately
   skips: a spaced or dotted 7-digit number ("751 6662", "751.6662"), 7 or more plain digits, or 10 or more digits
   with single separators (space . ( ) / -) between them. For a severity=warn test on the redacted text; it also
   flags legitimate text such as "SB 123 4567", which is why it only warns. #}
{% macro phone_like_digits_pattern() -%}
    (^|[^0-9])([0-9]{3}[ .][0-9]{4}|[0-9]{7,}|[0-9]([ .()/-]?[0-9]){9,})([^0-9]|$)
{%- endmacro %}

{% macro has_phone_like_digits(expr) -%}
    {{ mogov.regex_matches(expr, mogov.phone_like_digits_pattern()) }}
{%- endmacro %}
