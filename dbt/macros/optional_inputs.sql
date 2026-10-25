{#
  Optional raw inputs switch whole model groups on through vars (`enabled=var('mec_direct', false)`), and a
  model's `enabled` is fixed at parse time, so a hook cannot turn them on. `mogov build` sets the vars from
  what is on disk. A bare `dbt build` sets nothing, so it would quietly build without the MEC crosswalk and
  the CourtListener case bulk even when that data is loaded (issue #105). `check_optional_inputs`, run from
  on-run-start, makes that mistake loud: it fails when a var is false but its raw table exists.
  Opt out on purpose with --vars '{skip_optional_raw_check: true}'.
#}
{% macro raw_table_exists(identifier) -%}
    {{ return(adapter.dispatch('raw_table_exists', 'mogov')(identifier)) }}
{%- endmacro %}

{#- Backends without a way to look at the raw files report "no", which skips the check. -#}
{% macro default__raw_table_exists(identifier) -%}
    {% do log("optional-input check skipped: no raw-file lookup for this adapter", info=true) %}
    {{ return(false) }}
{%- endmacro %}

{#- Raw tables are directories of Parquet parts under MOGOV_RAW_DIR (see the sources' external_location);
    DuckDB's glob() returns no rows, rather than failing, when nothing matches. -#}
{% macro duckdb__raw_table_exists(identifier) -%}
    {% set pattern = (env_var('MOGOV_RAW_DIR', 'data/raw') ~ '/' ~ identifier ~ '/*.parquet').replace("'", "''") %}
    {% set found = run_query("select count(*) from glob('" ~ pattern ~ "')") %}
    {{ return(found.columns[0].values()[0] > 0) }}
{%- endmacro %}


{% macro check_optional_inputs() -%}
    {% if execute and not var('skip_optional_raw_check', false) %}
        {% set gates = {'mec_direct': 'mec_cd1_a', 'cl_case_bulk': 'cl_mo_opinion_clusters'} %}
        {% set wrong = [] %}
        {% for gate, identifier in gates.items() %}
            {% if not var(gate, false) and mogov.raw_table_exists(identifier) %}
                {% do wrong.append(gate ~ ' (raw table ' ~ identifier ~ ' exists)') %}
            {% endif %}
        {% endfor %}
        {% if wrong %}
            {{ exceptions.raise_compiler_error(
                "These optional inputs are loaded but their dbt vars are off, so their models would be silently"
                ~ " disabled: " ~ wrong | join(', ') ~ ". Build with `mogov build` (it sets the vars), or pass"
                ~ " --vars '{" ~ gates.keys() | join(': true, ') ~ ": true}'. To disable them on purpose, pass"
                ~ " --vars '{skip_optional_raw_check: true}'."
            ) }}
        {% endif %}
    {% endif %}
{%- endmacro %}
