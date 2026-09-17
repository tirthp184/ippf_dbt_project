{{ config(materialized = 'view') }}
/* Refugee/displaced-reach proxy: people reached in displacement-context
   disasters (Conflict / Displacement-Migration / Protracted). */
select
    d.calendar_year, cf.region_name, cf.country_name_display,
    dis.disaster_sub_category,
    sum(r.actual_people_reached) as people_reached_displacement,
    sum(r.people_affected_alert) as people_affected
from {{ ref('fact_hum_response') }} r
join {{ ref('dim_date') }} d            on r.date_key = d.date_key
join {{ ref('v_dim_country_flat') }} cf on r.country_key = cf.country_key
join {{ ref('dim_disaster') }} dis      on r.disaster_key = dis.disaster_key
where dis.displacement_context = true
group by 1,2,3,4
