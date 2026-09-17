{{ config(materialized = 'table') }}

/* Static reference dim from seed_service_type. Deterministic surrogate key
   ordered by name, plus Unknown (-1). */

with src as (
    select service_type_name, service_group, source_domain,
           is_srh, is_sgbv, is_total_rollup
    from {{ ref('seed_service_type') }}
)

select
    row_number() over (order by service_type_name) as service_type_key,
    service_type_name, service_group, source_domain,
    is_srh, is_sgbv, is_total_rollup
from src

union all
select -1, 'Unknown / Unresolved', null, null, null, null, null
