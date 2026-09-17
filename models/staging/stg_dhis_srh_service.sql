{{ config(materialized = 'view') }}

/*
  Mechanical cleanup only. Blank/space placeholder values (DH-04) become
  NULL here. is_total_rollup classification and conformance to Humanitarian
  service types happens downstream (int_dhis_service_conformed.sql).
*/

select
    try_cast(trim(year) as number(4))                 as reporting_year,
    nullif(trim(data_name), '')                       as service_type_name_raw,
    nullif(trim(country_name), '')                    as country_name,
    try_cast(nullif(trim(metric_value), '') as number(18,2)) as service_count,
    source_file,
    source_sheet,
    source_row_number,
    load_batch_id,
    load_ts
from {{ source('raw', 'raw_dhis_srh_service') }}
