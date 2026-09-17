{{ config(materialized = 'table') }}

/* Grain: MA x Year. Resolves MA via entity_code_num -> resolved_ma_key. */

with src as (
    select
        entity_code,
        regexp_substr(entity_code, '[0-9]+') as entity_code_num,
        reporting_year,
        ippf_income,
        intl_income_non_ippf,
        locally_generated_income,
        source_file
    from {{ ref('stg_total_income') }}
),

d as (select date_key, calendar_year from {{ ref('dim_date') }} where is_year_end = true),
ma as (select ma_key, entity_code_num from {{ ref('dim_member_association') }} where entity_code_num is not null)

select
    coalesce(d.date_key, -1)   as date_key,
    coalesce(ma.ma_key, -1)    as ma_key,
    src.ippf_income,
    src.intl_income_non_ippf,
    src.locally_generated_income,
    src.reporting_year,
    src.source_file,
    current_timestamp()        as load_ts
from src
left join d  on src.reporting_year = d.calendar_year
left join ma on src.entity_code_num = ma.entity_code_num
