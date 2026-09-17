{{ config(materialized = 'view') }}

/* Mechanical cleanup only. */

select
    nullif(trim(entity_code), '')                          as entity_code,
    try_cast(trim(year) as number(4))                      as reporting_year,
    try_cast(trim(ippf_income) as number(18,2))            as ippf_income,
    try_cast(trim(intl_income_non_ippf) as number(18,2))   as intl_income_non_ippf,
    try_cast(trim(locally_generated_income) as number(18,2)) as locally_generated_income,
    source_file,
    source_sheet,
    source_row_number,
    load_batch_id,
    load_ts
from {{ source('raw', 'raw_total_income') }}
