{{ config(materialized = 'table') }}

/* Grain: one row per humanitarian response event. REJECT rows (RG-02
   Vietnam, MA-02 SFPA, HU-03/04/05) are EXCLUDED here — only CONFIRMED
   responses load. start/end date_key resolve to REAL calendar dates
   (day grain), date_key to the reporting year-end. */

with src as (
    select * from {{ ref('int_humanitarian_response') }}
    where severity = 'CONFIRMED'
),

d as (select date_key, calendar_year from {{ ref('dim_date') }} where is_year_end = true),
dd as (select date_key, full_date from {{ ref('dim_date') }}),
c as (select country_key, iso_alpha3 from {{ ref('dim_country') }}),
ma as (select ma_key, resolved_ma_key from {{ ref('dim_member_association') }}),
dis as (select disaster_key, disaster_sub_category from {{ ref('dim_disaster') }}),
f as (select funding_key, funding_name from {{ ref('dim_funding') }})

select
    src.response_key,
    coalesce(d.date_key, -1)          as date_key,
    coalesce(sd.date_key, -1)         as start_date_key,
    coalesce(ed.date_key, -1)         as end_date_key,
    coalesce(ma.ma_key, -1)           as ma_key,
    coalesce(c.country_key, -1)       as country_key,
    coalesce(dis.disaster_key, -1)    as disaster_key,
    coalesce(f.funding_key, -1)       as funding_key,
    src.grant_usd,
    src.proposed_people_reach,
    src.actual_people_reached,
    src.people_affected_alert,
    src.est_people_affected_alert,
    src.deliveries_conducted,
    src.clean_delivery_kits,
    src.dignity_hygiene_kits,
    src.cyps,
    src.unintended_pregnancies_averted,
    src.maternal_deaths_averted,
    src.trainings_conducted,
    src.source_file,
    current_timestamp()               as load_ts
from src
left join d   on src.reporting_year = d.calendar_year
left join dd sd on src.start_date = sd.full_date
left join dd ed on src.end_date = ed.full_date
left join c   on src.country_iso3 = c.iso_alpha3
left join ma  on src.resolved_ma_key = ma.resolved_ma_key
left join dis on src.sub_category = dis.disaster_sub_category
left join f   on src.funding = f.funding_name
