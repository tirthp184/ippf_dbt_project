{{ config(materialized = 'view') }}
/*
  Exposes RAW.RAW_INGESTION_RUN_LOG (populated by 02_load_raw.py on every
  run, success or failure). This is the ingestion-side counterpart to
  v_pipeline_run_status (the dbt transformation side) — together they cover
  the full pipeline: Excel -> RAW -> STG -> EDW -> SEMANTIC.

  Not a dbt-managed table (created by the Python script via its own
  connection), so referenced here by fully qualified name, same pattern as
  v_pipeline_run_status.
*/

select
    load_batch_id,
    run_started_at,
    run_completed_at,
    duration_seconds,
    files_processed,
    status,
    error_message,
    datediff('hour', run_completed_at, current_timestamp()) as hours_since_last_ingestion,
    row_number() over (order by run_completed_at desc) = 1  as is_most_recent_run
from {{ target.database }}.RAW.RAW_INGESTION_RUN_LOG
order by run_completed_at desc