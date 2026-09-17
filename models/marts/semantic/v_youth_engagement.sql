{{ config(materialized = 'view') }}
/* Youth service share and youth-vs-adult client estimate. */
select
    d.calendar_year, cf.country_name_display, cf.region_name,
    sum(cp.srh_sr_0_24)  as youth_services,
    sum(cp.srh_sr_total) as total_services,
    div0(sum(cp.srh_sr_0_24), nullif(sum(cp.srh_sr_total),0)) as youth_service_pct,
    sum(cp.total_clients) - sum(cp.clients_10_24)            as adult_clients_est,
    sum(cp.clients_10_24)                                     as youth_clients
from {{ ref('fact_client_profile') }} cp
join {{ ref('dim_date') }} d           on cp.date_key = d.date_key
join {{ ref('v_dim_country_flat') }} cf on cp.country_key = cf.country_key
group by 1,2,3
