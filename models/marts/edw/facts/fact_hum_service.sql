{{ config(materialized = 'table') }}

/* Grain: response event x service type. response_key is a DEGENERATE
   dimension (no FK). Only services for CONFIRMED responses load — enforced
   by inner-joining to fact_hum_response (which already excludes REJECTs).
   Pulls date/ma/country/disaster context from the parent response so this
   fact carries its own conformed keys. */

with svc as (
    select * from {{ ref('int_humanitarian_service_unpivot') }}
),

parent as (
    select response_key, date_key, ma_key, country_key, disaster_key, funding_key
    from {{ ref('fact_hum_response') }}
),

st as (select service_type_key, service_type_name from {{ ref('dim_service_type') }})

select
    svc.response_key,
    p.date_key,
    p.ma_key,
    p.country_key,
    p.disaster_key,
    p.funding_key,
    coalesce(st.service_type_key, -1) as service_type_key,
    svc.service_count,
    current_timestamp()               as load_ts
from svc
inner join parent p
    on svc.response_key = p.response_key      -- inner join = only CONFIRMED responses
left join st
    on svc.service_type_name = st.service_type_name
