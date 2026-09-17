{{ config(materialized = 'view') }}

/*
  Mechanical cleanup only. Also fixes the verified trailing-space duplicate
  ('MISP' vs 'MISP ') by trimming training_topic — the two collapse to one
  value naturally once trimmed, no special-case needed.
*/

select
    try_cast(trim(year) as number(4))                 as reporting_year,
    nullif(trim(training_topic), '')                  as training_topic,
    nullif(trim(country), '')                         as country,
    try_cast(trim(training_number) as number(18,0))   as training_number,
    try_cast(trim(people_trend) as number(18,0))      as people_trained,
    nullif(trim(region), '')                          as region,
    nullif(trim(member_association), '')              as member_association,
    nullif(trim(funding), '')                         as funding,
    nullif(trim(conducted_by), '')                    as conducted_by,
    source_file,
    source_sheet,
    source_row_number,
    load_batch_id,
    load_ts
from {{ source('raw', 'raw_humanitarian_training') }}
