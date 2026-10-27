{#
    True when a group of bills has too many rows without a status (#750): more than `tolerance` rows AND more than
    `max_share` of the group. The absolute tolerance keeps a tiny special session (253 has 3 Senate bills) from
    failing the build over one rejected Actions fragment (#637), where 1 of 3 is 33%; a large session with a real
    gap (10% of 700 bills) still fails. Used by assert_senate_bills_mostly_have_status and proved on fixed inputs by
    assert_status_gap_tolerance.
#}
{% macro status_gap_exceeds(without_status, total, tolerance=2, max_share=0.05) -%}
    ({{ without_status }} > {{ tolerance }} and {{ without_status }} > {{ max_share }} * {{ total }})
{%- endmacro %}
