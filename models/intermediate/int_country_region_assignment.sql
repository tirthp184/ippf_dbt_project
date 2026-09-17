{{
  config(
    materialized = 'view'
  )
}}

/*
  Country -> Region assignment — locked logic:
    1. Source precedence: BP > DHIS > HUMANITARIAN > TRAINING
       (BP = formal membership/affiliation record; DHIS = systematic
       operational reporting; Humanitarian/Training = project/event-level,
       where a region tag may reflect cross-border response coordination
       rather than the country's true home region)
    2. The FIRST source (by precedence) to report a country's region sets
       the CANONICAL assignment.
    3. A later source reporting the SAME region -> just another confirming
       observation, no conflict.
    4. A later source reporting a DIFFERENT region -> CONFLICT. Per RG-02:
       the canonical stays as first-established; the CONFLICTING rows are
       flagged REJECT (held out of facts) -- not the country record itself.
       Example: Vietnam is ESEAOR per BP/DHIS; one Humanitarian row says AWR
       -> canonical stays ESEAOR, that Humanitarian row is rejected.

  This model does not filter anything out itself -- it produces the
  assignment + conflict flags. Fact-loading models are responsible for
  actually excluding rows where is_conflicting = true and severity = 'REJECT'.
*/

with country_resolved as (
    select
        normalized_key,
        raw_country_string,
        iso_alpha3,
        country_name_display,
        match_status as country_match_status
    from {{ ref('int_country_resolved') }}
),

region_resolved as (
    select
        source_system,
        raw_region_code,
        canonical_region_code,
        canonical_region_name,
        match_status as region_match_status
    from {{ ref('int_region_resolved') }}
),

-- Union every (country, region, source) observation across all sources that
-- carry BOTH a country and a region on the same row (directly, or derivable
-- from lineage). DHIS carries no explicit region column, but source_file
-- reliably identifies which regional export the row came from -- this is
-- what lets DHIS-only countries (no BP/Humanitarian/Training presence at
-- all, e.g. Cambodia/South Korea/Hong Kong) get a resolved region rather
-- than falling to Unknown for region as well as for MA (see DH-01: region
-- resolution here does NOT create an MA for them -- that gap is separate
-- and remains, since no organization exists in the source to attribute to).
raw_observations as (

    select
        'BP'                                    as source_system,
        1                                        as source_precedence,
        upper(trim(country_of_operation))        as raw_country_string,
        upper(trim(region))                      as raw_region_code
    from {{ source('raw', 'raw_membership_details') }}
    where country_of_operation is not null
      and region is not null

    union all

    -- DHIS: region derived from source_file (ESEAOR_DHIS2_Data.xlsx /
    -- SAR_DHIS2_Data.xlsx), country from the country_name column. Union
    -- across all 3 DHIS raw tables in case any country appears in only one
    -- of the three sheets.
    select
        'DHIS'                                   as source_system,
        2                                         as source_precedence,
        upper(trim(country_name))                as raw_country_string,
        case
            when source_file ilike 'ESEAOR%' then 'ESEAOR'
            when source_file ilike 'SAR%'    then 'SAR'
        end                                       as raw_region_code
    from {{ source('raw', 'raw_dhis_srh_service') }}
    where country_name is not null

    union

    select
        'DHIS'                                   as source_system,
        2                                         as source_precedence,
        upper(trim(country_name))                as raw_country_string,
        case
            when source_file ilike 'ESEAOR%' then 'ESEAOR'
            when source_file ilike 'SAR%'    then 'SAR'
        end                                       as raw_region_code
    from {{ source('raw', 'raw_dhis_cyp') }}
    where country_name is not null

    union

    select
        'DHIS'                                   as source_system,
        2                                         as source_precedence,
        upper(trim(country_name))                as raw_country_string,
        case
            when source_file ilike 'ESEAOR%' then 'ESEAOR'
            when source_file ilike 'SAR%'    then 'SAR'
        end                                       as raw_region_code
    from {{ source('raw', 'raw_dhis_clients_totals') }}
    where country_name is not null

    union all

    select
        'HUMANITARIAN'                          as source_system,
        3                                        as source_precedence,
        upper(trim(country))                     as raw_country_string,
        upper(trim(region))                      as raw_region_code
    from {{ source('raw', 'raw_humanitarian_er') }}
    where country is not null
      and region is not null

    union all

    select
        'TRAINING'                                as source_system,
        4                                          as source_precedence,
        upper(trim(country))                       as raw_country_string,
        upper(trim(region))                        as raw_region_code
    from {{ source('raw', 'raw_humanitarian_training') }}
    where country is not null
      and region is not null

),

-- Resolve each observation's country and region to their canonical forms.
observations_resolved as (

    select distinct
        o.source_system,
        o.source_precedence,
        cr.iso_alpha3,
        cr.country_name_display,
        rr.canonical_region_code,
        rr.canonical_region_name
    from raw_observations o
    left join country_resolved cr
        on o.raw_country_string = cr.normalized_key
    left join region_resolved rr
        on o.source_system = rr.source_system
       and o.raw_region_code = rr.raw_region_code
    where cr.iso_alpha3 is not null      -- exclude unresolved-country placeholders here;
                                          -- those are handled entirely by int_country_resolved's
                                          -- own NEEDS_REVIEW flag, not a region conflict
      and rr.canonical_region_code is not null

),

-- The canonical assignment per country = the region reported by the
-- highest-precedence (lowest number) source for that country.
canonical_assignment as (
    select
        iso_alpha3,
        country_name_display,
        canonical_region_code,
        canonical_region_name,
        source_system as canonical_source
    from observations_resolved
    qualify row_number() over (
        partition by iso_alpha3
        order by source_precedence asc
    ) = 1
),

-- Every observation, compared against that country's canonical assignment.
final as (
    select
        o.iso_alpha3,
        o.country_name_display,
        o.source_system                                    as observed_source,
        o.canonical_region_code                             as observed_region_code,
        ca.canonical_region_code,
        ca.canonical_region_name,
        ca.canonical_source,
        (o.canonical_region_code <> ca.canonical_region_code) as is_conflicting,
        case
            when o.canonical_region_code <> ca.canonical_region_code then 'NEEDS_REVIEW'
            else 'CONFIRMED'
        end as assignment_status,
        case
            when o.canonical_region_code <> ca.canonical_region_code
                then o.source_system || ' reported ' || o.canonical_region_code
                     || ' vs canonical ' || ca.canonical_region_code
                     || ' (from ' || ca.canonical_source || ')'
            else null
        end as review_note,
        case
            when o.canonical_region_code <> ca.canonical_region_code then 'REJECT'
            else 'CONFIRMED'
        end as severity
    from observations_resolved o
    inner join canonical_assignment ca
        on o.iso_alpha3 = ca.iso_alpha3
)

select
    iso_alpha3,
    country_name_display,
    observed_source,
    observed_region_code,
    canonical_region_code,
    canonical_region_name,
    canonical_source,
    is_conflicting,
    assignment_status,
    severity,
    review_note
from final