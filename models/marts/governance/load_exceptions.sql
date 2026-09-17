{{
  config(
    materialized = 'incremental',
    unique_key = 'exception_key',
    incremental_strategy = 'merge',
    schema = 'stg'
  )
}}

/*
  STG.LOAD_EXCEPTIONS — the central, persistent exception log.

  int_all_exceptions is a VIEW: it always reflects the CURRENT state of the
  pipeline (recomputed fresh every run from int_country_resolved,
  int_country_region_assignment, and future int_* branches). This model is
  the durable table built on top of it, so exceptions have history:

    - New exception this run          -> INSERT, first_detected_at = now
    - Same exception, still present   -> UPDATE, last_seen_at = now
                                          (first_detected_at untouched)
    - Exception no longer present     -> left as-is (not touched this run).
                                          A stale last_seen_at (older than the
                                          most recent run) is how you tell an
                                          exception has been resolved, without
                                          needing a separate is_resolved flag
                                          or a delete.

  exception_key is a hash of the natural key (source+type+subject+detail),
  not a random surrogate -- so the SAME real-world exception merges onto the
  SAME row every run, which is what makes the first/last_seen_at tracking work.
*/

with current_exceptions as (

    select
        exception_source,
        exception_type,
        subject,
        detail,
        severity,
        status,
        review_note,
        md5(
            coalesce(exception_source, '') || '|' ||
            coalesce(exception_type, '')   || '|' ||
            coalesce(subject, '')          || '|' ||
            coalesce(detail, '')
        ) as exception_key
    from {{ ref('int_all_exceptions') }}
    -- Dedup defensively: two rows sharing the exact same source+type+subject+
    -- detail represent the same reportable issue as far as this log is
    -- concerned, even if multiple underlying source rows produced it. MERGE
    -- requires a unique key on the source side, so this qualify is required,
    -- not optional.
    qualify row_number() over (
        partition by exception_key
        order by exception_source
    ) = 1

)

{% if is_incremental() %}
, existing as (
    select exception_key, first_detected_at
    from {{ this }}
)
{% endif %}

select
    ce.exception_key,
    ce.exception_source,
    ce.exception_type,
    ce.subject,
    ce.detail,
    ce.severity,
    ce.status,
    ce.review_note,
    '{{ invocation_id }}'      as load_batch_id,
    current_timestamp()        as last_seen_at,
    {% if is_incremental() %}
        coalesce(ex.first_detected_at, current_timestamp())
    {% else %}
        current_timestamp()
    {% endif %}                 as first_detected_at

from current_exceptions ce
{% if is_incremental() %}
left join existing ex
    on ex.exception_key = ce.exception_key
{% endif %}