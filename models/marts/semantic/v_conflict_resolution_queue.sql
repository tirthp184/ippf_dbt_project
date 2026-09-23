{{ config(materialized = 'view') }}

/*
  The single view the conflict-resolution app reads from. Combines the open
  exception queue with two things the app needs that v_data_quality_review_
  queue doesn't expose: whether a full quarantined row exists to show/
  reprocess, and whether this exception type is currently resolvable through
  the app at all (only MA-02 and CO-05 are wired into RESOLUTION_DECISIONS
  today -- see int_country_resolved.sql / int_ma_uin_resolved.sql).

  is_resolvable_via_app = FALSE doesn't mean "can't be fixed" -- it means
  "not yet wired into this mechanism"; e.g. RG-02 (region conflict) still
  requires a manual fix today, per the exception register.

  quarantined_row_count > 0 tells the app it has a full original row to
  show alongside the summary (join to STG.QUARANTINE_ROWS on exception_key).
*/

with open_exceptions as (
    select * from {{ ref('v_data_quality_review_queue') }}
),

quarantine_counts as (
    select exception_key, count(*) as quarantined_row_count
    from {{ target.database }}.STG.QUARANTINE_ROWS
    group by exception_key
),

existing_decisions as (
    select
        raw_key,
        decision_type,
        resolved_value,
        decided_by,
        decided_at,
        notes
    from {{ target.database }}.STG.RESOLUTION_DECISIONS
    where is_active
    qualify row_number() over (partition by raw_key, decision_type order by decided_at desc) = 1
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
    e.days_open,
    case
        when e.exception_type = 'MA-02' then 'MA_HOME_COUNTRY'
        when e.exception_type = 'CO-05' then 'COUNTRY'
        else null
    end                                                     as decision_type_required,
    e.exception_type in ('MA-02', 'CO-05')                  as is_resolvable_via_app,
    coalesce(q.quarantined_row_count, 0)                    as quarantined_row_count,
    d.decided_by                                             as prior_decision_by,
    d.decided_at                                             as prior_decision_at,
    d.resolved_value                                         as prior_decision_value
from open_exceptions e
left join quarantine_counts q
    on e.subject = q.exception_key
left join existing_decisions d
    on e.subject = d.raw_key
    and ((e.exception_type = 'MA-02' and d.decision_type = 'MA_HOME_COUNTRY')
      or (e.exception_type = 'CO-05' and d.decision_type = 'COUNTRY'))
order by e.severity desc, e.first_detected_at asc
