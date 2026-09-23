{{
  config(
    materialized = 'table',
    post_hook = "
      INSERT INTO {{ target.database }}.STG.QUARANTINE_ROWS
        (exception_key, source_table, source_row_number, load_batch_id, row_data)
      SELECT
        c.exception_key, c.source_table, c.source_row_number, c.load_batch_id, c.row_data
      FROM {{ this }} c
      WHERE NOT EXISTS (
        SELECT 1 FROM {{ target.database }}.STG.QUARANTINE_ROWS q
        WHERE q.source_table = c.source_table
          AND q.source_row_number = c.source_row_number
      )
    "
  )
}}

/*
  Identifies every Humanitarian ER record currently REJECTed (RG-02 region
  conflict or MA-02 multi-country conflict — see int_humanitarian_response),
  and snapshots its FULL original row. response_key = source_row_number
  gives a direct 1:1 join back to RAW.

  This model's own table ({{ this }}) is just the freshly-computed candidate
  set for THIS run. The post_hook then INSERTs any candidates not already in
  STG.QUARANTINE_ROWS -- so the shared table only ever grows via new finds,
  and is never wiped by a re-run. QUARANTINE_ROWS is a stable, app-writable
  table: once a steward resolves a decision (see RESOLUTION_DECISIONS),
  removing/marking the corresponding row here is the app's responsibility,
  not dbt's.

  Scope note: this covers the one row-level REJECT case in the pipeline
  today. Value-level exceptions (a flagged acronym or country string that
  could appear across many rows/files, e.g. SFPA itself) aren't "one row" to
  quarantine -- those are handled via RESOLUTION_DECISIONS directly, not
  this table.
*/

with rejects as (
    select
        response_key,
        severity,
        review_note,
        resolved_ma_key,
        country_name_display
    from {{ ref('int_humanitarian_response') }}
    where severity = 'REJECT'
),

raw_rows as (
    select
        source_row_number,
        load_batch_id,
        object_construct(*) as row_data
    from {{ source('raw', 'raw_humanitarian_er') }}
)

select
    -- Matches load_exceptions.subject exactly for each conflict type, so the
    -- app can join quarantine rows to the review queue on this value: MA-02
    -- uses resolved_ma_key (int_all_exceptions.ma_multi_country_conflicts),
    -- RG-02 uses country_name_display (int_all_exceptions.country_region_conflicts).
    case
        when r.review_note ilike 'MA-02%' then r.resolved_ma_key
        when r.review_note ilike 'RG-02%' then r.country_name_display
        else r.review_note
    end                                     as exception_key,
    'RAW_HUMANITARIAN_ER'                  as source_table,
    r.response_key                         as source_row_number,
    raw.load_batch_id,
    raw.row_data
from rejects r
inner join raw_rows raw
    on r.response_key = raw.source_row_number