{{ config(materialized = 'view') }}

/*
  Conforms DHIS's 12 CYP method metrics (verified exact names) to their
  clinical classification (LARC/SARC/Permanent/Barrier) via
  seed_contraceptive_method. Same country->MA linking pattern as
  int_dhis_service_conformed.sql.
*/

with base as (
    select
        reporting_year,
        method_name_raw,
        country_name,
        cyp_value,
        source_file
    from {{ ref('stg_dhis_cyp') }}
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
        b.method_name_raw,
        b.cyp_value,
        b.source_file
    from base b
    left join country_lookup c
        on upper(trim(b.country_name)) = c.normalized_key
    left join {{ ref('int_country_to_ma_map') }} m
        on c.iso_alpha3 = m.home_country_iso3
)

select
    r.reporting_year,
    r.country_iso3,
    r.resolved_ma_key,
    sm.method_name_raw                            as method_name,
    sm.method_category,
    sm.is_total_rollup,
    r.cyp_value,
    r.source_file
from resolved r
inner join {{ ref('seed_contraceptive_method') }} sm
    on r.method_name_raw = sm.method_name_raw
where r.cyp_value is not null