{{ config(materialized = 'view') }}
/* Full client-reach analytics from DHIS client totals. Previously only the
   youth slice was exposed (v_youth_engagement). sdp_count is SEMI-ADDITIVE —
   do NOT sum it across years; use the latest year or a max, not a total. */
select
    d.calendar_year,
    cf.region_name, cf.country_name_display, cf.iso_alpha3,
    maf.ma_uin, maf.affiliate_name,
    sum(f.total_clients)             as total_clients,
    sum(f.female_clients)            as female_clients,
    sum(f.clients_10_19)             as adolescent_clients_10_19,
    sum(f.clients_10_24)             as youth_clients_10_24,
    sum(f.poor_vulnerable_clients)   as poor_vulnerable_clients,
    sum(f.srh_sr_total)              as srh_services_total,
    sum(f.srh_sr_0_24)               as srh_services_youth,
    max(f.sdp_count)                 as sdp_count_semi_additive,
    div0(sum(f.female_clients), nullif(sum(f.total_clients),0))          as female_client_share,
    div0(sum(f.poor_vulnerable_clients), nullif(sum(f.total_clients),0)) as poor_vulnerable_share,
    div0(sum(f.clients_10_24), nullif(sum(f.total_clients),0))           as youth_client_share
from {{ ref('fact_client_profile') }} f
join {{ ref('dim_date') }} d              on f.date_key = d.date_key
join {{ ref('v_dim_country_flat') }} cf   on f.country_key = cf.country_key
left join {{ ref('v_dim_ma_flat') }} maf  on f.ma_key = maf.ma_key
group by 1,2,3,4,5,6
