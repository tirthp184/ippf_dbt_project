{{ config(materialized = 'view') }}
/* Core SRH service delivery from DHIS. Previously NO semantic coverage.
   is_total_rollup rows are the source's own pre-aggregated totals — exposed
   separately so BI can either use them OR sum the detail, never both
   (double-counting guard). */
select
    d.calendar_year,
    cf.region_name, cf.country_name_display, cf.iso_alpha3,
    maf.ma_uin, maf.affiliate_name,
    st.service_type_name, st.service_group, st.is_srh, st.is_sgbv, st.is_total_rollup,
    sum(f.service_count) as services_delivered
from {{ ref('fact_dhis_service') }} f
join {{ ref('dim_date') }} d              on f.date_key = d.date_key
join {{ ref('v_dim_country_flat') }} cf   on f.country_key = cf.country_key
left join {{ ref('v_dim_ma_flat') }} maf  on f.ma_key = maf.ma_key
join {{ ref('dim_service_type') }} st     on f.service_type_key = st.service_type_key
group by 1,2,3,4,5,6,7,8,9,10,11
