{# Redact contact strings from free text, keeping the rest of the sentence. This project keeps citizens' email
   addresses and phone numbers in raw and join keys only (never in models or exports), so staging replaces just
   the address or number with a marker instead of dropping the whole text. Patterns are POSIX ERE (see
   compat/strings.sql). A public official's office phone is redacted too: the pattern cannot tell whose it is.
   Email: local part, @, a dotted host; a sentence-ending dot after the host stays outside the match.
   Phone: 3-3-4 digits split by space, dot or dash, with optional parentheses on the area code. #}
{% macro redact_contact(expr) -%}
    {{ mogov.regex_replace_all(
        mogov.regex_replace_all(expr, '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+([.][A-Za-z0-9-]+)+', '[email removed]'),
        '[(]?[0-9]{3}[)]?[ .-][0-9]{3}[ .-][0-9]{4}',
        '[phone removed]'
    ) }}
{%- endmacro %}

{# SQL boolean: the text still holds an email address, a phone number or a stray @. For build-failing guards. #}
{% macro has_contact_string(expr) -%}
    ({{ expr }} like '%@%' or {{ mogov.regex_matches(expr, '[(]?[0-9]{3}[)]?[ .-][0-9]{3}[ .-][0-9]{4}') }})
{%- endmacro %}
