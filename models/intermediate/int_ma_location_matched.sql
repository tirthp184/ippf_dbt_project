{{ config(materialized = 'view') }}

/*
  Matches seed_ma_location (27 MAs, synthetic/illustrative coordinates - see
  the seed's source note) to real dim_member_association records by name.

  NOT matched by country: the seed has TWO MAs for Bangladesh (Bandhu Social
  Welfare Society and Population Services and Training Center), so a
  country-only join would be ambiguous/wrong for that one country. Name
  matching is required.

  Match method: case-insensitive CONTAINS in both directions, since
  dim_member_association.affiliate_name may carry a trailing acronym in
  parentheses (e.g. "Bandhu Social Welfare Society (Bandhu)") that the seed's
  plain name doesn't have. This is a best-effort match over a small (27-row)
  manually curated list - flagged, not silently trusted, per the same
  transparency principle as every other resolution step in this pipeline.
*/

with seed as (
    select
        ma_name_reference,
        country_reference,
        sample_location_city,
        latitude,
        longitude
    from {{ ref('seed_ma_location') }}
),

ma as (
    select
        ma_key,
        ma_uin,
        affiliate_name,
        ma_acronym,
        org_type
    from {{ ref('dim_member_association') }}
    where ma_key <> -1
      and org_type = 'Member Association'
      and affiliate_name is not null
),

matched as (
    select
        s.ma_name_reference,
        s.country_reference,
        s.sample_location_city,
        s.latitude,
        s.longitude,
        m.ma_key,
        m.ma_uin,
        m.affiliate_name as matched_affiliate_name,
        case
            when lower(m.affiliate_name) like '%' || lower(s.ma_name_reference) || '%'
              or lower(s.ma_name_reference) like '%' || lower(m.affiliate_name) || '%'
            then 'MATCHED'
            else null
        end as match_status
    from seed s
    left join ma m
        on lower(m.affiliate_name) like '%' || lower(s.ma_name_reference) || '%'
        or lower(s.ma_name_reference) like '%' || lower(m.affiliate_name) || '%'
)

select
    ma_name_reference,
    country_reference,
    sample_location_city,
    latitude,
    longitude,
    ma_key,
    ma_uin,
    matched_affiliate_name,
    coalesce(match_status, 'NEEDS_REVIEW') as match_status
from matched

-- Dedup safety net: if a seed name matches more than one MA record, or an MA
-- record matches more than one seed row, keep exactly one pairing rather
-- than fanning out (same defensive pattern used in dim_country).
qualify row_number() over (
    partition by ma_name_reference
    order by ma_key
) = 1
