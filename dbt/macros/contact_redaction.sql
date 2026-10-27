{# Redact contact strings from free text, keeping the rest of the sentence. This project keeps citizens' email
   addresses and phone numbers in raw and join keys only (never in models or exports), so staging replaces just
   the address or number with a marker instead of dropping the whole text. Patterns are POSIX ERE (see
   compat/strings.sql). A public official's office phone is redacted too: the pattern cannot tell whose it is.
   Email: local part, @, a dotted host; a sentence-ending dot after the host stays outside the match.
   Phone (one pattern, contact_phone_pattern, shared by redaction and the guard): a 10-digit number whose
   separators (space, dot, dash) may be absent, optional parentheses on the area code, a leading +1 or 1, and a
   trailing extension (ext. 12, x12); or the 7-digit Capitol office form 751-6662 (space or dash only, so
   RSMo 135.1150 stays). Both sit between non-digits, so ranges (2001-2013), dates and amounts are not caught. #}
{# Groups: 1 = the character before, 6 = the character after (both kept on replacement). #}
{% macro contact_phone_pattern() -%}
    (^|[^0-9])(([+]?1[ .-]?)?[(]?[0-9]{3}[)]?[ .-]?[0-9]{3}[ .-]?[0-9]{4}|[0-9]{3}[ -][0-9]{4})([ ]?(ext[.]?|EXT[.]?|Ext[.]?|x|X)[ ]?[0-9]{1,5})?([^0-9]|$)
{%- endmacro %}

{% macro redact_contact(expr) -%}
    {%- set no_email = mogov.regex_replace_all(expr, '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+([.][A-Za-z0-9-]+)+', '[email removed]') -%}
    {#- Twice: the character after one number is the character before the next ("751-6662 or 751-1167"). -#}
    {{ mogov.regex_replace_all(
        mogov.regex_replace_all(no_email, mogov.contact_phone_pattern(), '\\1[phone removed]\\6'),
        mogov.contact_phone_pattern(),
        '\\1[phone removed]\\6'
    ) }}
{%- endmacro %}

{# SQL boolean: the text still holds an email address, a phone number or a stray @. For build-failing guards. #}
{% macro has_contact_string(expr) -%}
    ({{ expr }} like '%@%' or {{ mogov.regex_matches(expr, mogov.contact_phone_pattern()) }})
{%- endmacro %}
