{{ config(materialized = 'table') }}

/* Static reference dim from seed_training_topic. The trailing-space dup
   ('MISP' vs 'MISP ') was already resolved by trim in stg_humanitarian_training;
   the seed's std name is the canonical value. */

with src as (
    select distinct
        training_topic_name_std as training_topic_name,
        is_safeguarding, is_youth_related
    from {{ ref('seed_training_topic') }}
)

select
    row_number() over (order by training_topic_name) as training_topic_key,
    training_topic_name, is_safeguarding, is_youth_related
from src

union all
select -1, 'Unknown / Unresolved', null, null
