{{ config(materialized = 'table') }}

/* Grain: Year x Country x Method (+ MA via country link). */

with src as (
    select * from {{ ref('int_dhis_cyp_conformed') }}
),

d as (select date_key, calendar_year from {{ ref('dim_date') }} where is_year_end = true),
c as (select country_key, iso_alpha3 from {{ ref('dim_country') }}),
ma as (select ma_key, resolved_ma_key from {{ ref('dim_member_association') }}),
m as (select method_key, method_name from {{ ref('dim_contraceptive_method') }})

select
    coalesce(d.date_key, -1)      as date_key,
    coalesce(c.country_key, -1)   as country_key,
    coalesce(ma.ma_key, -1)       as ma_key,
    coalesce(m.method_key, -1)    as method_key,
    src.cyp_value,
    src.source_file,
    current_timestamp()           as load_ts
from src
left join d  on src.reporting_year = d.calendar_year
left join c  on src.country_iso3 = c.iso_alpha3
left join ma on src.resolved_ma_key = ma.resolved_ma_key
left join m  on src.method_name = m.method_name