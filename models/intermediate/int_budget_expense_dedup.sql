{{ config(materialized = 'view') }}

/*
  Same G1 pattern as int_budget_focus_area_dedup.sql, applied to the Expense
  sheet's declared grain (MA x Year x Project x Expense Category).
  Verified 4 duplicate-grain cases in ESEAOR 2024.
*/

with cleaned as (
    select
        entity_code,
        regexp_substr(entity_code, '[0-9]+')     as entity_code_num,
        reporting_year,
        project_name,
        expense_category,
        budget_amount,
        actual_amount,
        source_file
    from {{ ref('stg_budget_expense') }}
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
    expense_category,
    sum(coalesce(budget_amount, 0))                as budget_amount,
    sum(coalesce(actual_amount, 0))                as actual_amount,
    count(*)                                       as src_line_count,
    max(source_file)                               as source_file,
    boolor_agg(has_negative_amount)                as has_negative_amount_flag,
    boolor_agg(has_null_amount)                    as has_null_amount_flag
from flagged
group by resolved_ma_key, entity_code_num, reporting_year, project_name, expense_category
