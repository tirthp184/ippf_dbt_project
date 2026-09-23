{#
  Creates the two tables the conflict-resolution app reads from and writes
  to. Run at on-run-start (see dbt_project.yml) so they exist before any
  model queries them -- same pattern as create_pipeline_run_log_table().

  RESOLUTION_DECISIONS is written to directly by the app (not by dbt) when
  a steward resolves a flagged conflict. int_country_resolved and
  int_ma_uin_resolved check it FIRST, before running their own matching
  logic, so a human decision always takes precedence.

  QUARANTINE_ROWS holds a full snapshot of the ORIGINAL row for row-level
  REJECT cases (e.g. Humanitarian rows dropped for RG-02/MA-02), so the app
  has something to show and reprocess. VARIANT keeps it generic across
  source tables with different schemas.
#}
{% macro create_resolution_tables() %}
  {% if execute %}

    {% set create_decisions_sql %}
      CREATE TABLE IF NOT EXISTS {{ target.database }}.STG.RESOLUTION_DECISIONS (
        decision_id     STRING DEFAULT UUID_STRING(),
        exception_key   STRING,
        decision_type   STRING,   -- 'COUNTRY' | 'MA_HOME_COUNTRY'
        raw_key         STRING,   -- normalized_key (country) or ma_acronym (MA)
        resolved_value  STRING,   -- iso_alpha3 in both current decision types
        decided_by      STRING,
        decided_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
        notes           STRING,
        is_active       BOOLEAN DEFAULT TRUE
      )
    {% endset %}
    {% do run_query(create_decisions_sql) %}

    {% set create_quarantine_sql %}
      CREATE TABLE IF NOT EXISTS {{ target.database }}.STG.QUARANTINE_ROWS (
        quarantine_id      STRING DEFAULT UUID_STRING(),
        exception_key       STRING,
        source_table         STRING,
        source_row_number    NUMBER,
        load_batch_id         STRING,
        row_data                VARIANT,
        quarantined_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
      )
    {% endset %}
    {% do run_query(create_quarantine_sql) %}

  {% endif %}
{% endmacro %}
