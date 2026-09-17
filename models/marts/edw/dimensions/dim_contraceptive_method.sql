{{ config(materialized = 'table') }}

/* Static reference dim from seed_contraceptive_method. */

with src as (
    select method_name_raw as method_name, method_category, is_total_rollup
    from {{ ref('seed_contraceptive_method') }}
)

select
    row_number() over (order by method_name) as method_key,
    method_name, method_category, is_total_rollup
from src

union all
select -1, 'Unknown / Unresolved', null, null
