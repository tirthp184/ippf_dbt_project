{{ config(materialized = 'view') }}

/* Mechanical cleanup only. G1 aggregation handled downstream. */

select
    nullif(trim(entity_code), '')                     as entity_code,
    try_cast(trim(year) as number(4))                 as reporting_year,
    nullif(trim(project_name), '')                    as project_name,
    nullif(trim(expense_category), '')                as expense_category,
    try_cast(trim(budget_amount) as number(18,2))     as budget_amount,
    try_cast(trim(actual_amount) as number(18,2))     as actual_amount,
    source_file,
    source_sheet,
    source_row_number,
    load_batch_id,
    load_ts
from {{ source('raw', 'raw_budget_expense') }}
