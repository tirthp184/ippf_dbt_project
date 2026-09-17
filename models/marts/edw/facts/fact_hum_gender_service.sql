{{ config(materialized = 'table') }}

/* Grain: response event x gender x service mode. Same degenerate response_key
   + CONFIRMED-only inner join pattern as fact_hum_service. */

with gs as (
    select * from {{ ref('int_humanitarian_gender_service_unpivot') }}
),

parent as (
    select response_key, date_key, ma_key, country_key, disaster_key
    from {{ ref('fact_hum_response') }}
),

g as (select gender_key, gender from {{ ref('dim_gender') }}),
sm as (select service_mode_key, service_mode from {{ ref('dim_service_mode') }})

select
    gs.response_key,
    p.date_key,
    p.ma_key,
    p.country_key,
    p.disaster_key,
    coalesce(g.gender_key, -1)        as gender_key,
    coalesce(sm.service_mode_key, -1) as service_mode_key,
    gs.service_count,
    current_timestamp()               as load_ts
from gs
inner join parent p
    on gs.response_key = p.response_key
left join g  on gs.gender = g.gender
left join sm on gs.service_mode = sm.service_mode
