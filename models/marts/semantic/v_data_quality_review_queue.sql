{{
  config(
    materialized = 'view'
  )
}}

/*
  Open-exception review queue for IPPF data stewards / the POC demo.

  "Open" = last_seen_at falls within the most recent run's batch. Anything
  with an older last_seen_at was present in a past run but did NOT reappear
  in the latest run -- i.e. it has been resolved upstream (the source data,
  a seed, or an override was fixed) and is kept in load_exceptions only for
  historical audit, not shown here as something needing action.
*/

with most_recent_batch as (
    select max(last_seen_at) as latest_run_ts
    from {{ ref('load_exceptions') }}
)

select
    e.exception_type,
    e.exception_source,
    e.subject,
    e.detail,
    e.severity,
    e.status,
    e.review_note,
    e.first_detected_at,
    e.last_seen_at,
    datediff('day', e.first_detected_at, e.last_seen_at) as days_open
from {{ ref('load_exceptions') }} e
cross join most_recent_batch b
where e.last_seen_at = b.latest_run_ts   -- still present in the latest run = still open
order by e.severity desc, e.first_detected_at asc
