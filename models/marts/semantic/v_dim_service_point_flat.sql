{{ config(materialized = 'view') }}
/* Flat service-point dim for GIS: MA + country + region + coordinates. */
select
    sp.service_point_key,
    sp.service_point_name,
    sp.service_point_type,
    sp.latitude,
    sp.longitude,
    sp.coordinate_source,
    ma.ma_uin,
    ma.affiliate_name,
    c.country_name_display as country_name,
    g.region_code,
    g.region_name
from {{ ref('dim_service_point') }} sp
left join {{ ref('dim_member_association') }} ma on sp.ma_key = ma.ma_key
left join {{ ref('dim_country') }} c            on sp.country_key = c.country_key
left join {{ ref('dim_geography') }} g          on c.geography_key = g.geography_key
