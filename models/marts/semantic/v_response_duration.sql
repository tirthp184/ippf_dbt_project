{{ config(materialized = 'view') }}
/* Humanitarian response duration in days, per response event. */
select
    d.calendar_year, cf.region_name, cf.country_name_display,
    dis.disaster_sub_category,
    r.response_key,
    sd.full_date as start_date, ed.full_date as end_date,
    datediff('day', sd.full_date, ed.full_date) as response_duration_days
from {{ ref('fact_hum_response') }} r
join {{ ref('dim_date') }} d            on r.date_key = d.date_key
join {{ ref('dim_date') }} sd           on r.start_date_key = sd.date_key
join {{ ref('dim_date') }} ed           on r.end_date_key = ed.date_key
join {{ ref('v_dim_country_flat') }} cf on r.country_key = cf.country_key
join {{ ref('dim_disaster') }} dis      on r.disaster_key = dis.disaster_key
