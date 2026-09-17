{{ config(materialized = 'table') }}

/* Focus area + strategic priority pulled live from source (verified 1:1),
   with is_advocacy / is_youth_related computed inline via name pattern —
   no seed (a new focus area next year gets flags applied automatically). */

with src as (
    select distinct focus_area, strategic_priority
    from {{ ref('stg_budget_focus_area') }}
    where focus_area is not null
)

select
    row_number() over (order by focus_area) as focus_area_key,
    focus_area          as focus_area_name,
    strategic_priority  as strategic_priority_name,
    (lower(focus_area) like '%advocacy%')                       as is_advocacy,
    (lower(focus_area) like '%cse%' or lower(focus_area) like '%youth%') as is_youth_related
from src

union all
select -1, 'Unknown / Unresolved', null, null, null
