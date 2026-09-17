{{ config(materialized = 'view') }}
/* SGBV/specialised service volume (safeguarding effort - service side). */
select
    d.calendar_year, cf.region_name, cf.country_name_display,
    sum(hs.service_count) as sgbv_services
from {{ ref('fact_hum_service') }} hs
join {{ ref('dim_date') }} d            on hs.date_key = d.date_key
join {{ ref('v_dim_country_flat') }} cf on hs.country_key = cf.country_key
join {{ ref('dim_service_type') }} st   on hs.service_type_key = st.service_type_key
where st.is_sgbv = true
group by 1,2,3
