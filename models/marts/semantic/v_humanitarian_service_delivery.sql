{{ config(materialized = 'view') }}
/* All humanitarian service delivery by conformed service type. Previously
   only the SGBV slice was exposed (v_safeguarding_services). Conforms to the
   SAME dim_service_type as v_srh_service_delivery, so DHIS and Humanitarian
   service volumes are comparable on a like-for-like basis. */
select
    d.calendar_year,
    cf.region_name, cf.country_name_display, cf.iso_alpha3,
    maf.ma_uin, maf.affiliate_name,
    dis.disaster_sub_category, dis.displacement_context,
    fu.funding_name,
    st.service_type_name, st.service_group, st.is_srh, st.is_sgbv, st.is_total_rollup,
    sum(hs.service_count) as services_delivered
from {{ ref('fact_hum_service') }} hs
join {{ ref('dim_date') }} d              on hs.date_key = d.date_key
join {{ ref('v_dim_country_flat') }} cf   on hs.country_key = cf.country_key
left join {{ ref('v_dim_ma_flat') }} maf  on hs.ma_key = maf.ma_key
join {{ ref('dim_disaster') }} dis        on hs.disaster_key = dis.disaster_key
join {{ ref('dim_funding') }} fu          on hs.funding_key = fu.funding_key
join {{ ref('dim_service_type') }} st     on hs.service_type_key = st.service_type_key
group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14
