{{ config(materialized = 'table') }}

/* Grain: Year x MA x Country x Training Topic x Funding. Includes IPPF
   Secretariat-conducted training (MA resolves to IPPF-MA-0000). conducted_by
   kept as a degenerate descriptive column. */

with src as (
    select
        reporting_year,
        training_topic,
        upper(trim(country))              as raw_country,
        upper(trim(member_association))   as ma_acronym,
        funding,
        conducted_by,
        training_number,
        people_trained,
        source_file
    from {{ ref('stg_humanitarian_training') }}
),

cr as (select normalized_key, iso_alpha3 from {{ ref('int_country_resolved') }}),
d as (select date_key, calendar_year from {{ ref('dim_date') }} where is_year_end = true),
c as (select country_key, iso_alpha3 from {{ ref('dim_country') }}),
ma as (select ma_key, ma_acronym from {{ ref('dim_member_association') }}),
tt as (select training_topic_key, training_topic_name from {{ ref('dim_training_topic') }}),
f as (select funding_key, funding_name from {{ ref('dim_funding') }})

select
    coalesce(d.date_key, -1)              as date_key,
    coalesce(ma.ma_key, -1)              as ma_key,
    coalesce(c.country_key, -1)          as country_key,
    coalesce(tt.training_topic_key, -1)  as training_topic_key,
    coalesce(f.funding_key, -1)          as funding_key,
    src.conducted_by,
    src.training_number                   as training_count,
    src.people_trained,
    src.source_file,
    current_timestamp()                   as load_ts
from src
left join cr on src.raw_country = cr.normalized_key
left join d  on src.reporting_year = d.calendar_year
left join c  on cr.iso_alpha3 = c.iso_alpha3
left join ma on src.ma_acronym = ma.ma_acronym
left join tt on src.training_topic = tt.training_topic_name
left join f  on src.funding = f.funding_name