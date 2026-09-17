{{ config(materialized = 'view') }}

/*
  Conforms DHIS's 13 SRH Service Delivery metrics (verified exact names) to
  the shared service_type_name used by seed_service_type — the same
  dimension Humanitarian's service unpivot conforms to, so DHIS and
  Humanitarian service counts roll up together in the EDW.

  DH-01: countries with no BP-listed MA (Cambodia, Hong Kong, DPRK, Laos,
  Marshall Islands, Republic of Korea) get resolved_ma_key = null here —
  downstream EDW fact loading routes these to the Unknown MA member + WARN.
*/

with base as (
    select
        reporting_year,
        service_type_name_raw,
        country_name,
        service_count,
        source_file
    from {{ ref('stg_dhis_srh_service') }}
),

country_lookup as (
    select normalized_key, iso_alpha3
    from {{ ref('int_country_resolved') }}
),

resolved as (
    select
        b.reporting_year,
        c.iso_alpha3                              as country_iso3,
        m.resolved_ma_key,
        b.service_type_name_raw,
        b.service_count,
        b.source_file
    from base b
    left join country_lookup c
        on upper(trim(b.country_name)) = c.normalized_key
    left join {{ ref('int_country_to_ma_map') }} m
        on c.iso_alpha3 = m.home_country_iso3
),

service_type_lookup as (
    select service_type_name, is_srh, is_sgbv, is_total_rollup
    from {{ ref('seed_service_type') }}
    where source_domain = 'DHIS'
)

select
    r.reporting_year,
    r.country_iso3,
    r.resolved_ma_key,
    st.service_type_name,
    st.is_srh,
    st.is_sgbv,
    st.is_total_rollup,
    r.service_count,
    r.source_file
from resolved r
inner join service_type_lookup st
    on r.service_type_name_raw = st.service_type_name
where r.service_count is not null