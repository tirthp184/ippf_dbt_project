{{ config(materialized = 'table') }}

/* Grain: Year x Country (+ MA via country link). Pivots the DHIS "Clients
   and Service Totals" sheet (kept long in staging) into the typed-column
   shape, using the 8 verified exact metric names. sdp_count is
   semi-additive (do NOT sum across years). */

with src as (
    select
        reporting_year,
        country_name,
        metric_name_raw,
        metric_value,
        source_file
    from {{ ref('stg_dhis_clients_totals') }}
),

pivoted as (
    select
        reporting_year,
        country_name,
        max(iff(metric_name_raw = 'Estimated clients aged 10-19', metric_value, null))            as clients_10_19,
        max(iff(metric_name_raw = 'Estimated clients aged 10-24', metric_value, null))            as clients_10_24,
        max(iff(metric_name_raw = 'Estimated female clients', metric_value, null))                as female_clients,
        max(iff(metric_name_raw = 'Estimated poor and/or vulnerable clients', metric_value, null)) as poor_vulnerable_clients,
        max(iff(metric_name_raw = 'Estimated total clients', metric_value, null))                 as total_clients,
        max(iff(metric_name_raw = 'SRH S+R 0 - 24', metric_value, null))                          as srh_sr_0_24,
        max(iff(metric_name_raw = 'SRH S+R Total', metric_value, null))                           as srh_sr_total,
        max(iff(metric_name_raw = 'SDP - Number of SDPs per type', metric_value, null))           as sdp_count,
        max(source_file)                                                                          as source_file
    from src
    group by reporting_year, country_name
),

resolved as (
    select
        p.*,
        cr.iso_alpha3 as country_iso3
    from pivoted p
    left join {{ ref('int_country_resolved') }} cr
        on upper(trim(p.country_name)) = cr.normalized_key
),

d as (select date_key, calendar_year from {{ ref('dim_date') }} where is_year_end = true),
c as (select country_key, iso_alpha3 from {{ ref('dim_country') }}),
ma_map as (select home_country_iso3, resolved_ma_key from {{ ref('int_country_to_ma_map') }}),
ma as (select ma_key, resolved_ma_key from {{ ref('dim_member_association') }})

select
    coalesce(d.date_key, -1)     as date_key,
    coalesce(c.country_key, -1)  as country_key,
    coalesce(ma.ma_key, -1)      as ma_key,
    r.clients_10_19,
    r.clients_10_24,
    r.female_clients,
    r.poor_vulnerable_clients,
    r.total_clients,
    r.srh_sr_0_24,
    r.srh_sr_total,
    r.sdp_count,
    r.source_file,
    current_timestamp()          as load_ts
from resolved r
left join d      on r.reporting_year = d.calendar_year
left join c      on r.country_iso3 = c.iso_alpha3
left join ma_map on r.country_iso3 = ma_map.home_country_iso3
left join ma     on ma_map.resolved_ma_key = ma.resolved_ma_key