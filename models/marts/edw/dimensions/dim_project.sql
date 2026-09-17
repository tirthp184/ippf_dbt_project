{{ config(materialized = 'table') }}

/* Project descriptor, distinct across both budget sheets. Materialized as a
   table (not incremental) for the POC — if project-level trend continuity
   across runs becomes important, promote to incremental like the identity
   dims. */

with src as (
    select distinct project_name from {{ ref('stg_budget_focus_area') }} where project_name is not null
    union
    select distinct project_name from {{ ref('stg_budget_expense') }} where project_name is not null
)

select
    row_number() over (order by project_name) as project_key,
    project_name
from src

union all
select -1, 'Unknown / Unresolved'
