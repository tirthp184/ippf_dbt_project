{{ config(materialized = 'table') }}

/*
  Static, full-refresh table — region is a closed, IPPF-defined set of 6
  that never auto-expands (locked decision). Surrogate key via ROW_NUMBER
  ordered alphabetically by region_code — deterministic regardless of CSV
  row order, so this is stable across full rebuilds even without MERGE.

  geography_key = -1 reserved for Unknown, so no fact/dim ever orphans.
*/

with canonical as (
    select region_code, region_name
    from {{ ref('seed_region_canonical') }}
),

numbered as (
    select
        row_number() over (order by region_code) as geography_key,
        region_code,
        region_name
    from canonical
)

select geography_key, region_code, region_name from numbered

union all

select -1 as geography_key, 'UNKNOWN' as region_code, 'Unknown / Unresolved' as region_name
