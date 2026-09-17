{{ config(materialized = 'view') }}

/* Mechanical cleanup only. Method classification (LARC/SARC/etc, via
   seed_contraceptive_method) happens downstream. */

select
    try_cast(trim(year) as number(4))                 as reporting_year,
    nullif(trim(data_name), '')                       as method_name_raw,
    nullif(trim(country_name), '')                    as country_name,
    try_cast(nullif(trim(metric_value), '') as number(18,2)) as cyp_value,
    source_file,
    source_sheet,
    source_row_number,
    load_batch_id,
    load_ts
from {{ source('raw', 'raw_dhis_cyp') }}
