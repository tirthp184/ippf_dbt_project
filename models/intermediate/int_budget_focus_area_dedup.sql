{{ config(materialized = 'view') }}

/*
  G1 (Exception Register FN-01): the source export contains duplicate lines
  that share the full declared grain (MA x Year x Project x Focus Area) but
  carry different amounts — verified 16 such cases in ESEAOR 2024 alone.
  Resolution: SUM the amounts at the declared grain, record src_line_count
  so the collapse is auditable (feeds reconciliation).

  Also applies, generically (not just the sample instances already found):
    FN-02 (negative amount)      -> WARN, loaded as-is
    FN-03 (null/blank amount)    -> WARN, treated as 0 in the SUM (NULL would
                                    otherwise silently zero out the whole
                                    grain's sum via standard SQL NULL rules
                                    if not coalesced)

  MA resolution: joins to int_ma_uin_resolved via entity_code_num (BP's
  stable natural key) to get resolved_ma_key for downstream fact-building.
  BP-sourced entities never hit the MA-02 (multi-country) REJECT rule, so no
  severity filtering is needed on that join here.
*/

with cleaned as (
    select
        entity_code,
        regexp_substr(entity_code, '[0-9]+')     as entity_code_num,
        reporting_year,
        project_name,
        focus_area,
        strategic_priority,
        budget_amount,
        actual_amount,
        source_file
    from {{ ref('stg_budget_focus_area') }}
),

ma_lookup as (
    select entity_code_num, resolved_ma_key
    from {{ ref('int_ma_uin_resolved') }}
    where entity_code_num is not null
),

flagged as (
    select
        c.*,
        m.resolved_ma_key,
        (c.budget_amount < 0 or c.actual_amount < 0)          as has_negative_amount,
        (c.budget_amount is null or c.actual_amount is null)  as has_null_amount
    from cleaned c
    left join ma_lookup m
        on c.entity_code_num = m.entity_code_num
)

select
    resolved_ma_key,
    entity_code_num,
    reporting_year,
    project_name,
    focus_area,
    -- strategic_priority verified strictly 1:1 with focus_area — safe to take any value per group
    max(strategic_priority)                       as strategic_priority,
    sum(coalesce(budget_amount, 0))                as budget_amount,
    sum(coalesce(actual_amount, 0))                as actual_amount,
    count(*)                                       as src_line_count,
    max(source_file)                               as source_file,
    boolor_agg(has_negative_amount)                as has_negative_amount_flag,
    boolor_agg(has_null_amount)                    as has_null_amount_flag
from flagged
group by resolved_ma_key, entity_code_num, reporting_year, project_name, focus_area
