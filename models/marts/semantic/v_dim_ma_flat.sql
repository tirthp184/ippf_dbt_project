{{ config(materialized = 'view') }}
/* Flat MA dim: UIN, org attributes, and home country/region pre-joined. */
select
    ma.ma_key,
    ma.ma_uin,
    ma.org_type,
    ma.ma_acronym,
    ma.affiliate_name,
    ma.organisation_name_en,
    ma.has_business_plan,
    ma.source_systems,
    c.country_name_display as home_country_name,
    c.iso_alpha3           as home_country_iso3,
    g.region_code,
    g.region_name
from {{ ref('dim_member_association') }} ma
left join {{ ref('dim_country') }} c   on ma.home_country_key = c.country_key
left join {{ ref('dim_geography') }} g on c.geography_key = g.geography_key
