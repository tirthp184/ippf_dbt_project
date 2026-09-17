{{ config(materialized = 'table') }}

/* Grain: MA x Year x Project x Expense Category. */

with src as (
    select * from {{ ref('int_budget_expense_dedup') }}
),

d as (select date_key, calendar_year from {{ ref('dim_date') }} where is_year_end = true),
ma as (select ma_key, resolved_ma_key from {{ ref('dim_member_association') }}),
p as (select project_key, project_name from {{ ref('dim_project') }}),
ec as (select expense_category_key, expense_category_name from {{ ref('dim_expense_category') }})

select
    coalesce(d.date_key, -1)                as date_key,
    coalesce(ma.ma_key, -1)                 as ma_key,
    coalesce(p.project_key, -1)             as project_key,
    coalesce(ec.expense_category_key, -1)   as expense_category_key,
    src.budget_amount,
    src.actual_amount,
    src.src_line_count,
    src.reporting_year,
    src.source_file,
    current_timestamp()                     as load_ts
from src
left join d  on src.reporting_year = d.calendar_year
left join ma on src.resolved_ma_key = ma.resolved_ma_key
left join p  on src.project_name = p.project_name
left join ec on src.expense_category = ec.expense_category_name
