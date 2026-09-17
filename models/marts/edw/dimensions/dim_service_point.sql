{{ config(materialized = 'table') }}

/* GIS / drill-down leaf. POC grain = one service point per MA (its HQ).
   Coordinates come from int_ma_location_matched where a match exists —
   these are SYNTHETIC/ILLUSTRATIVE points (a representative city inside the
   MA's country, typically the capital), NOT verified real HQ addresses. See
   seed_ma_location's source note. Any MA the 27-row reference list doesn't
   cover falls back to NULL, coordinate_source = 'PLACEHOLDER', exactly as
   before. Never present this layer as verified office locations — label any
   map built on it "Illustrative MA Locations". */

with ma as (
    select
        ma_key,
        ma_uin,
        affiliate_name,
        home_country_key,
        org_type
    from {{ ref('dim_member_association') }}
    where ma_key <> -1
      and org_type = 'Member Association'   -- Secretariat has no service point
),

loc as (
    select ma_key, latitude, longitude, sample_location_city, match_status
    from {{ ref('int_ma_location_matched') }}
    where match_status = 'MATCHED'
)

select
    row_number() over (order by ma.ma_key)              as service_point_key,
    coalesce(ma.affiliate_name, ma.ma_uin) || ' (HQ)'    as service_point_name,
    'MA HQ'                                              as service_point_type,
    ma.ma_key,
    ma.home_country_key                                  as country_key,
    loc.latitude,
    loc.longitude,
    case when loc.latitude is not null
         then 'SYNTHETIC_ILLUSTRATIVE'
         else 'PLACEHOLDER'
    end                                                   as coordinate_source,
    true                                                  as is_active
from ma
left join loc on ma.ma_key = loc.ma_key

union all
select -1, 'Unknown / Unresolved', null, -1, -1, null, null, 'PLACEHOLDER', false

