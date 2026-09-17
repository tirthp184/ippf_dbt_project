{{ config(materialized = 'table') }}

/* Grain: MA x Year x Project x Focus Area. Amounts already G1-aggregated
   upstream in int_budget_focus_area_dedup. date_key resolves to the
   year-end row of dim_date (annual grain). */

with src as (
    select * from {{ ref('int_budget_focus_area_dedup') }}
),

d as (select date_key, calendar_year from {{ ref('dim_date') }} where is_year_end = true),
ma as (select ma_key, resolved_ma_key from {{ ref('dim_member_association') }}),
p as (select project_key, project_name from {{ ref('dim_project') }}),
fa as (select focus_area_key, focus_area_name from {{ ref('dim_focus_area') }})

select
    coalesce(d.date_key, -1)          as date_key,
    coalesce(ma.ma_key, -1)           as ma_key,
    coalesce(p.project_key, -1)       as project_key,
    coalesce(fa.focus_area_key, -1)   as focus_area_key,
    src.budget_amount,
    src.actual_amount,
    src.src_line_count,
    src.reporting_year,
    src.source_file,
    current_timestamp()               as load_ts
from src
left join d  on src.reporting_year = d.calendar_year
left join ma on src.resolved_ma_key = ma.resolved_ma_key
left join p  on src.project_name = p.project_name
left join fa on src.focus_area = fa.focus_area_name
