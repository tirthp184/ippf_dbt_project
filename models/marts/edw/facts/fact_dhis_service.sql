{{ config(materialized = 'table') }}

/* Grain: Year x Country x Service Type (+ MA via country link). Conformed
   upstream in int_dhis_service_conformed. */

with src as (
    select * from {{ ref('int_dhis_service_conformed') }}
),

d as (select date_key, calendar_year from {{ ref('dim_date') }} where is_year_end = true),
c as (select country_key, iso_alpha3 from {{ ref('dim_country') }}),
ma as (select ma_key, resolved_ma_key from {{ ref('dim_member_association') }}),
st as (select service_type_key, service_type_name from {{ ref('dim_service_type') }})

select
    coalesce(d.date_key, -1)            as date_key,
    coalesce(c.country_key, -1)         as country_key,
    coalesce(ma.ma_key, -1)             as ma_key,
    coalesce(st.service_type_key, -1)   as service_type_key,
    src.service_count,
    src.source_file,
    current_timestamp()                 as load_ts
from src
left join d  on src.reporting_year = d.calendar_year
left join c  on src.country_iso3 = c.iso_alpha3
left join ma on src.resolved_ma_key = ma.resolved_ma_key
left join st on src.service_type_name = st.service_type_name