-- depends_on: {{ ref('official_profile') }}
-- Coverage status text is shown to readers (cell and sentence on every profile). It must carry no instructions to the
-- maintainer: no seed or file paths, no "add finds" or to-do notes (#829). Every *_status column is checked, so a
-- new one is covered without editing this test.
{% set status_columns = [] %}
{% if execute %}
    {% for col in adapter.get_columns_in_relation(ref('official_profile')) %}
        {% if col.name.endswith('_status') %}
            {% do status_columns.append(col.name) %}
        {% endif %}
    {% endfor %}
{% endif %}

with statuses as (
    {% for col in status_columns %}
        select
            official_id,
            '{{ col }}' as status_column,
            {{ col }} as status
        from {{ ref('official_profile') }}
        {% if not loop.last %}
            union all
        {% endif %}
    {% else %}
        select
            cast(null as varchar) as official_id,
            cast(null as varchar) as status_column,
            cast(null as varchar) as status
        where 1 = 0
    {% endfor %}
)

select
    official_id,
    status_column,
    status
from statuses
where
    lower(status) like '%seeds/%'
    or lower(status) like '%.csv%'
    or lower(status) like '%add finds%'
    or lower(status) like '%todo%'
