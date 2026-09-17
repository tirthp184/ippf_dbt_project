{{ config(materialized = 'table') }}

/* Persists int_country_region_assignment (the source-precedence canonical
   region + Vietnam-style conflict tracking) as a queryable table, resolving
   country to its surrogate key. This is the governed record of "which region
   owns which country" plus every conflicting observation, for audit. */

with assignment as (
    select * from {{ ref('int_country_region_assignment') }}
),

ctry as (select country_key, iso_alpha3 from {{ ref('dim_country') }})

select
    row_number() over (order by a.iso_alpha3, a.observed_source) as assignment_key,
    c.country_key,
    a.iso_alpha3,
    a.country_name_display,
    a.observed_source                        as source_system,
    a.observed_region_code,
    a.canonical_region_code,
    a.canonical_source,
    a.is_conflicting,
    a.assignment_status,
    a.review_note
from assignment a
left join ctry c on a.iso_alpha3 = c.iso_alpha3
