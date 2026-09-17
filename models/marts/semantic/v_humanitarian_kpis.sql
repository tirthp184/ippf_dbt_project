{{ config(materialized = 'view') }}
/* Core humanitarian response KPIs. Previously only the displacement subset
   and response duration were exposed.
   NOTE reach_achievement_rate: 79 of 133 sample responses exceed their
   proposed reach (over-achievement is normal in humanitarian response), so
   values >1.0 are expected, not errors. */
select
    d.calendar_year,
    cf.region_name, cf.country_name_display, cf.iso_alpha3,
    maf.ma_uin, maf.affiliate_name,
    dis.disaster_category, dis.disaster_sub_category, dis.displacement_context,
    fu.funding_name,
    sum(r.grant_usd)                        as grant_usd,
    sum(r.proposed_people_reach)            as proposed_people_reach,
    sum(r.actual_people_reached)            as actual_people_reached,
    sum(r.est_people_affected_alert)        as est_people_affected,
    sum(r.cyps)                             as cyps,
    sum(r.unintended_pregnancies_averted)   as unintended_pregnancies_averted,
    sum(r.maternal_deaths_averted)          as maternal_deaths_averted,
    sum(r.deliveries_conducted)             as deliveries_conducted,
    sum(r.clean_delivery_kits)              as clean_delivery_kits,
    sum(r.dignity_hygiene_kits)             as dignity_hygiene_kits,
    sum(r.trainings_conducted)              as trainings_conducted,
    count(distinct r.response_key)          as response_count,
    div0(sum(r.actual_people_reached), nullif(sum(r.proposed_people_reach),0)) as reach_achievement_rate,
    div0(sum(r.grant_usd), nullif(sum(r.actual_people_reached),0))             as cost_per_person_reached,
    div0(sum(r.actual_people_reached), nullif(sum(r.est_people_affected_alert),0)) as coverage_of_affected
from {{ ref('fact_hum_response') }} r
join {{ ref('dim_date') }} d              on r.date_key = d.date_key
join {{ ref('v_dim_country_flat') }} cf   on r.country_key = cf.country_key
left join {{ ref('v_dim_ma_flat') }} maf  on r.ma_key = maf.ma_key
join {{ ref('dim_disaster') }} dis        on r.disaster_key = dis.disaster_key
join {{ ref('dim_funding') }} fu          on r.funding_key = fu.funding_key
group by 1,2,3,4,5,6,7,8,9,10
