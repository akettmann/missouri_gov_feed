{# Text extracted from a PDF with the characters that cannot be text removed: NUL, which small-caps and some
   display glyphs extract as, and the other C0 control characters and DEL except tab, line feed and carriage
   return. The letter a NUL stood for is not recoverable from the text, so it is dropped, not guessed. A NUL in
   a text column breaks exports and some backends, so nothing downstream of staging sees one. Null stays null. #}
{% macro clean_pdf_text(expr) -%}
    {{ mogov.regex_replace_all(expr, '[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f]+', '') }}
{%- endmacro %}
