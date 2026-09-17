{{ config(materialized = 'table') }}

/* Disaster taxonomy pulled live from Humanitarian ER source. displacement_
   context (the refugee-reach proxy) is an explicit list — no textual pattern
   links Conflict/Displacement/Protracted, so it stays an inline IN-list
   rather than a keyword rule or a seed. */

with src as (
    select distinct
        disasters_category   as disaster_category,
        sub_category         as disaster_sub_category
    from {{ ref('stg_humanitarian_er') }}
    where sub_category is not null
)

select
    row_number() over (order by disaster_category, disaster_sub_category) as disaster_key,
    disaster_category,
    disaster_sub_category,
    (disaster_sub_category in ('Conflict','Displacement/Migration','Protracted')) as displacement_context
from src

union all
select -1, 'Unknown / Unresolved', 'Unknown / Unresolved', null
