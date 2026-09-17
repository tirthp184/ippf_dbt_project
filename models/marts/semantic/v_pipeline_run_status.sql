{{ config(materialized = 'view') }}
/*
  Exposes STG.PIPELINE_RUN_LOG (populated by the on-run-end hook in
  macros/log_pipeline_run.sql) for BI/Cortex consumption. Answers "when did
  the pipeline last run, did it succeed, how long did it take."

  Note: PIPELINE_RUN_LOG is created via run_query in the hook, not as a dbt
  model, so it has no ref() -- referenced here by fully qualified name.
*/

select
    invocation_id,
    run_started_at,
    run_completed_at,
    duration_seconds,
    total_models,
    succeeded,
    failed,
    skipped,
    overall_status,
    dbt_target,
    datediff('hour', run_completed_at, current_timestamp()) as hours_since_last_run,
    row_number() over (order by run_completed_at desc) = 1  as is_most_recent_run
from {{ target.database }}.STG.PIPELINE_RUN_LOG
order by run_completed_at desc
