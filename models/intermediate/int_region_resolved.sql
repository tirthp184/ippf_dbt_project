{{
  config(
    materialized = 'view'
  )
}}

/*
  Region code resolution — locked logic:
    1. Exact match against the 6 canonical codes first (no transform)
    2. Only if no exact match: strip a trailing "O", retry
    3. Still no match -> Unknown (-1), flagged NEEDS_REVIEW
       (regions are a closed, IPPF-defined set of 6 -- NEVER auto-create a 7th)

  This model is source-agnostic: it takes a raw region-code string + which
  source it came from, and returns the resolved canonical code/name plus
  match metadata. Callers (int_country_region_assignment, int_ma_uin_resolved,
  fact loaders) union their raw region observations into this shape.
*/

with canonical as (
    select region_code, region_name
    from {{ ref('seed_region_canonical') }}
),

-- Every source that carries a region code, normalized into one shape.
-- Extend this CTE as new sources are added -- nothing downstream changes.
raw_region_observations as (

    select distinct
        'HUMANITARIAN'                          as source_system,
        upper(trim(region))                     as raw_region_code
    from {{ source('raw', 'raw_humanitarian_er') }}
    where region is not null

    union all

    select distinct
        'TRAINING'                               as source_system,
        upper(trim(region))                      as raw_region_code
    from {{ source('raw', 'raw_humanitarian_training') }}
    where region is not null

    union all

    -- Business Plan doesn't carry an explicit region column in Membership
    -- Details -- the region is implicit in which yearly file the row came
    -- from (ESEAOR_*.xlsx / SAR_*.xlsx), captured via source_file at
    -- ingestion. Extract it here rather than re-deriving downstream.
    select distinct
        'BP'                                      as source_system,
        upper(trim(region))                        as raw_region_code
    from {{ source('raw', 'raw_membership_details') }}
    where region is not null

    union all

    -- DHIS has NO region column at all (only Year/Metric/Country). Region is
    -- implicit in which file the data came from (ESEAOR_DHIS2_Data.xlsx /
    -- SAR_DHIS2_Data.xlsx) -- derived from source_file, the same lineage
    -- column every RAW table already carries. This is what lets DHIS-only
    -- countries (e.g. Cambodia, South Korea, Hong Kong -- which have no BP/
    -- Humanitarian/Training presence at all) still get a resolved region,
    -- rather than falling to Unknown for region as well as for MA.
    select distinct
        'DHIS'                                    as source_system,
        case
            when source_file ilike 'ESEAOR%' then 'ESEAOR'
            when source_file ilike 'SAR%'    then 'SAR'
        end                                        as raw_region_code
    from {{ source('raw', 'raw_dhis_srh_service') }}
    where source_file is not null

),

resolved as (

    select
        source_system,
        raw_region_code,

        -- Step 1: exact match
        coalesce(
            c_exact.region_code,
            -- Step 2: only tried if step 1 found nothing -- strip trailing "O"
            c_stripped.region_code
        )                                            as canonical_region_code,

        coalesce(
            c_exact.region_name,
            c_stripped.region_name
        )                                            as canonical_region_name,

        case
            when c_exact.region_code is not null    then 'EXACT'
            when c_stripped.region_code is not null then 'NORMALIZED_STRIP_O'
            else 'NONE'
        end                                          as match_method,

        case
            when c_exact.region_code is not null                  then 'CONFIRMED'
            when c_stripped.region_code is not null                then 'CONFIRMED'
            else 'NEEDS_REVIEW'
        end                                          as match_status

    from raw_region_observations o
    left join canonical c_exact
        on o.raw_region_code = c_exact.region_code
    left join canonical c_stripped
        on c_exact.region_code is null                                    -- only attempt step 2 if step 1 missed
       and rtrim(o.raw_region_code, 'O') = c_stripped.region_code
       and o.raw_region_code <> c_stripped.region_code                    -- guard: don't strip a code that has no trailing O to begin with
)

select
    source_system,
    raw_region_code,
    canonical_region_code,
    canonical_region_name,
    match_method,
    match_status
from resolved