{{ config(materialized = 'table') }}

/* Funding streams, union-sourced across Humanitarian ER and Training
   (SRHiEP appears only in Training — CX-01). */

with src as (
    select distinct funding from {{ ref('stg_humanitarian_er') }} where funding is not null
    union
    select distinct funding from {{ ref('stg_humanitarian_training') }} where funding is not null
)

select
    row_number() over (order by funding) as funding_key,
    funding as funding_name
from src

union all
select -1, 'Unknown / Unresolved'
