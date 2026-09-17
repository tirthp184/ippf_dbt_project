{{ config(materialized = 'view') }}
/* Gender-disaggregated humanitarian service delivery + female share. */
select
    d.calendar_year, cf.region_name, cf.country_name_display, sm.service_mode,
    sum(iff(g.gender='Female',     gs.service_count,0)) as female_services,
    sum(iff(g.gender='Male',       gs.service_count,0)) as male_services,
    sum(iff(g.gender='Non-Binary', gs.service_count,0)) as nonbinary_services,
    div0(sum(iff(g.gender='Female',gs.service_count,0)), nullif(sum(gs.service_count),0)) as female_share
from {{ ref('fact_hum_gender_service') }} gs
join {{ ref('dim_date') }} d            on gs.date_key = d.date_key
join {{ ref('v_dim_country_flat') }} cf on gs.country_key = cf.country_key
join {{ ref('dim_gender') }} g          on gs.gender_key = g.gender_key
join {{ ref('dim_service_mode') }} sm   on gs.service_mode_key = sm.service_mode_key
group by 1,2,3,4
