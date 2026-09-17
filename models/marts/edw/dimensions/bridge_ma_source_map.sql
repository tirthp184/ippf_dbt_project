{{ config(materialized = 'incremental', unique_key = ['ma_key', 'source_system']) }}

/*
  The Approach-1 identity registry as an actual queryable table — one row
  per (organization, source system) natural-key mapping. This is what lets
  someone answer "what does source X call this org" or "which UIN does
  entity_code 303 belong to" without re-deriving it from int_ma_uin_resolved
  every time.

  Explodes int_ma_uin_resolved's comma-joined source_systems into one row
  per source, pairing each with its actual natural key for that source
  (entity_code_num for BP, ma_acronym for Humanitarian/Training).
*/

with resolved as (
    select
        resolved_ma_key,
        entity_code_num,
        ma_acronym,
        source_systems,
        match_method,
        match_confidence,
        match_status
    from {{ ref('int_ma_uin_resolved') }}
    where severity <> 'REJECT'
),

ma_lookup as (
    select ma_key, resolved_ma_key from {{ ref('dim_member_association') }}
),

exploded as (
    select
        r.resolved_ma_key,
        r.entity_code_num,
        r.ma_acronym,
        trim(s.value)                                  as source_system,
        r.match_method,
        r.match_confidence,
        r.match_status
    from resolved r,
    lateral split_to_table(r.source_systems, ',') s
),

with_natural_key as (
    select
        resolved_ma_key,
        source_system,
        case
            when source_system = 'BP' then entity_code_num
            else ma_acronym
        end                                             as source_natural_key,
        match_method,
        match_confidence,
        match_status
    from exploded
)

select
    m.ma_key,
    w.source_system,
    w.source_natural_key,
    w.match_method,
    w.match_confidence,
    w.match_status                                     as match_status,
    current_date()                                      as valid_from,
    date '9999-12-31'                                   as valid_to
from with_natural_key w
inner join ma_lookup m
    on w.resolved_ma_key = m.resolved_ma_key

{% if is_incremental() %}
where (m.ma_key, w.source_system) not in (
    select ma_key, source_system from {{ this }}
)
{% endif %}
