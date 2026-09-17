{{ config(materialized = 'view') }}

/*
  Mechanical cleanup only — no business logic. Casts, trims, blank->NULL.
  Business/identity resolution (UIN, country) happens downstream in the
  int_* models, not here.
*/

select
    nullif(trim(region), '')                          as region,
    nullif(trim(affiliate_name), '')                  as affiliate_name,
    nullif(trim(country_of_operation), '')            as country_of_operation,
    nullif(trim(entity_code), '')                     as entity_code,
    try_cast(trim(year) as number(4))                 as reporting_year,
    nullif(trim(organisation_name_en), '')            as organisation_name_en,
    nullif(trim(organisation_name), '')               as organisation_name,
    nullif(trim(primary_contact), '')                 as primary_contact,
    nullif(trim(contact_email), '')                   as contact_email,
    try_cast(trim(grant_y1_usd) as number(18,2))              as grant_y1_usd,
    try_cast(trim(grant_y2_provisional_usd) as number(18,2))  as grant_y2_provisional_usd,
    try_cast(trim(grant_y3_provisional_usd) as number(18,2))  as grant_y3_provisional_usd,
    source_file,
    source_sheet,
    source_row_number,
    load_batch_id,
    load_ts
from {{ source('raw', 'raw_membership_details') }}
