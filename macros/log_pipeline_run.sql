{#
  Two macros solving a sequencing problem: v_pipeline_run_status (a MODEL)
  runs during the main model phase, but PIPELINE_RUN_LOG's row-insert can
  only happen in on-run-end (once results are known). If table creation also
  waited until on-run-end, the very first run would fail — the model would
  try to select from a table that doesn't exist yet. So table creation runs
  in on-run-start (before any model), and the insert runs in on-run-end
  (after all models) — see dbt_project.yml.
#}

{% macro create_pipeline_run_log_table() %}
  {% if execute %}
    {% set create_sql %}
      CREATE TABLE IF NOT EXISTS {{ target.database }}.STG.PIPELINE_RUN_LOG (
        invocation_id      STRING,
        run_started_at     TIMESTAMP_NTZ,
        run_completed_at   TIMESTAMP_NTZ,
        duration_seconds   NUMBER,
        total_models       NUMBER,
        succeeded          NUMBER,
        failed             NUMBER,
        skipped            NUMBER,
        overall_status     STRING,
        dbt_target         STRING
      )
    {% endset %}
    {% do run_query(create_sql) %}
  {% endif %}
{% endmacro %}

{% macro log_pipeline_run() %}
  {% if execute %}
    {% set success_count = results | selectattr("status", "in", ["success","pass"]) | list | length %}
    {% set error_count   = results | selectattr("status", "in", ["error","fail"])   | list | length %}
    {% set skip_count    = results | selectattr("status", "==", "skipped")          | list | length %}
    {% set total_count   = results | length %}
    {% set overall_status = 'SUCCESS' if error_count == 0 else 'FAILED' %}

    {% set insert_sql %}
      INSERT INTO {{ target.database }}.STG.PIPELINE_RUN_LOG
      SELECT
        '{{ invocation_id }}',
        '{{ run_started_at }}'::timestamp_ntz,
        current_timestamp()::timestamp_ntz,
        datediff('second', '{{ run_started_at }}'::timestamp_ntz, current_timestamp()),
        {{ total_count }},
        {{ success_count }},
        {{ error_count }},
        {{ skip_count }},
        '{{ overall_status }}',
        '{{ target.name }}'
    {% endset %}
    {% do run_query(insert_sql) %}
  {% endif %}
{% endmacro %}