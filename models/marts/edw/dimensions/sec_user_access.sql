{{ config(materialized = 'table') }}

/* RBAC/RLS demo table. Resolves the seed's human-readable scope
   (region_code / country_iso3 / ma_uin) to surrogate keys for row-level
   security joins. NULL scope key = unrestricted at that level. */

with seed as (
    select * from {{ ref('seed_user_access') }}
),

geo as (select geography_key, region_code from {{ ref('dim_geography') }}),
ctry as (select country_key, iso_alpha3 from {{ ref('dim_country') }}),
ma as (select ma_key, ma_uin from {{ ref('dim_member_association') }})

select
    row_number() over (order by s.user_email, s.function_role) as access_key,
    s.user_email,
    g.geography_key,
    c.country_key,
    m.ma_key,
    s.function_role,
    s.access_level,
    true as is_active
from seed s
left join geo  g on nullif(s.region_code, '')  = g.region_code
left join ctry c on nullif(s.country_iso3, '') = c.iso_alpha3
left join ma   m on nullif(s.ma_uin, '')       = m.ma_uin
