{{ config(materialized = 'view') }}
/* Flat country dim: region hierarchy pre-joined so BI/Cortex import one wide
   object instead of traversing DIM_COUNTRY -> DIM_GEOGRAPHY. */
select
    c.country_key,
    c.iso_alpha3,
    c.country_name_display,
    c.match_status as country_match_status,
    g.region_code,
    g.region_name
from {{ ref('dim_country') }} c
left join {{ ref('dim_geography') }} g on c.geography_key = g.geography_key
