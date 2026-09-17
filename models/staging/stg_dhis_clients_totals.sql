{{ config(materialized = 'view') }}

/* Mechanical cleanup only. Pivoting the 6 client metrics into typed columns
   (FACT_CLIENT_PROFILE's shape) happens downstream, not here — this stays
   in the same long/unpivoted shape as the other two DHIS staging models
   for consistency. */

select
    try_cast(trim(year) as number(4))                 as reporting_year,
    nullif(trim(data_name), '')                       as metric_name_raw,
    nullif(trim(country_name), '')                    as country_name,
    try_cast(nullif(trim(metric_value), '') as number(18,2)) as metric_value,
    source_file,
    source_sheet,
    source_row_number,
    load_batch_id,
    load_ts
from {{ source('raw', 'raw_dhis_clients_totals') }}
