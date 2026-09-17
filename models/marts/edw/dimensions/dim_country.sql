{{ config(materialized = 'incremental', unique_key = 'business_key') }}

/*
  Incremental (MERGE) — country_key must survive re-runs since facts store
  it. business_key = iso_alpha3 for resolved countries, or the normalized
  raw string itself for unresolved placeholders (iso_alpha3 is NULL there —
  see int_country_resolved's step4_placeholder). This guarantees every
  distinct real-world country AND every distinct unresolved placeholder
  gets exactly one stable row.

  POC SCOPE DECISION: this model is insert-only for new business keys on
  each run — it does not update descriptive attributes of already-loaded
  countries (no SCD versioning). This is what guarantees country_key never
  shifts for existing rows; a fuller build would add SCD-1/2 attribute
  updates on top of this same key-stability guarantee.

  geography_key resolves via int_country_region_assignment's canonical
  region for this country; falls back to Unknown (-1) for countries that
  never appear in a BP/Humanitarian/Training row with a region (e.g. a
  DHIS-only country with no other source presence).
*/

with resolved_countries as (
    -- Multiple raw strings can resolve to the same iso_alpha3 (e.g. exact +
    -- override matches for spelling variants of the same country), each
    -- potentially carrying a different match_method/source_systems. Must
    -- dedupe to exactly ONE row per iso_alpha3 here, or dim_country ends up
    -- with 2 physical rows for the same business_key, fanning out every
    -- downstream join (this caused duplicate MA rows in
    -- dim_member_association). SELECT DISTINCT is NOT sufficient - it only
    -- removes fully-identical rows, not rows sharing iso_alpha3 with
    -- differing match_method. QUALIFY picks the single most trustworthy
    -- match per country: OVERRIDE > EXACT > FUZZY.
    select
        iso_alpha3                                as business_key,
        iso_alpha3,
        country_name_display,
        match_method,
        match_confidence,
        match_status,
        source_systems
    from {{ ref('int_country_resolved') }}
    where iso_alpha3 is not null
    qualify row_number() over (
        partition by iso_alpha3
        order by
            case match_method
                when 'OVERRIDE' then 1
                when 'EXACT' then 2
                when 'FUZZY' then 3
                else 4
            end,
            match_confidence desc nulls last
    ) = 1
),

placeholder_countries as (
    select distinct
        normalized_key                            as business_key,
        null                                       as iso_alpha3,
        country_name_display,
        match_method,
        match_confidence,
        match_status,
        source_systems
    from {{ ref('int_country_resolved') }}
    where iso_alpha3 is null
),

all_countries as (
    select * from resolved_countries
    union all
    select * from placeholder_countries
),

region_assignment as (
    select distinct iso_alpha3, canonical_region_code
    from {{ ref('int_country_region_assignment') }}
),

geo_lookup as (
    select geography_key, region_code from {{ ref('dim_geography') }}
),

with_geo as (
    select
        a.*,
        coalesce(g.geography_key, -1) as geography_key
    from all_countries a
    left join region_assignment ra
        on a.iso_alpha3 = ra.iso_alpha3
    left join geo_lookup g
        on ra.canonical_region_code = g.region_code
),

new_rows as (
    select *
    from with_geo
    {% if is_incremental() %}
    where business_key not in (select business_key from {{ this }})
    {% endif %}
),

{% if is_incremental() %}
max_existing as (
    select coalesce(max(country_key), 0) as max_key from {{ this }}
),
{% else %}
max_existing as (select 0 as max_key),
{% endif %}

numbered as (
    select
        n.*,
        m.max_key + row_number() over (order by n.business_key) as country_key
    from new_rows n
    cross join max_existing m
)

select
    country_key,
    business_key,
    iso_alpha3,
    country_name_display,
    country_name_display as country_name_iso_official,  -- refined once a dedicated ISO-official lookup is joined; display name used for both for now
    geography_key,
    match_method,
    match_confidence,
    match_status,
    source_systems
from numbered

{% if not is_incremental() %}
union all
select -1, 'UNKNOWN', null, 'Unknown / Unresolved', 'Unknown / Unresolved', -1, 'NONE', null, 'CONFIRMED', null
{% endif %}