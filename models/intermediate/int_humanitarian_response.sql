{{ config(materialized = 'view') }}

/*
  Header stream of the Humanitarian ER 3-way split (HU-01). Grain: one row
  per response event = one source row. response_key is the source row's own
  source_row_number — already guaranteed unique per row by the ingestion
  script (assigned sequentially per sheet) and stable across re-runs as long
  as the source file's row order doesn't change. It is a DEGENERATE
  DIMENSION on this and the two sibling unpivot models below — no FK
  relationship between them, only a shared traceability value (fix #4 from
  the schema review: avoids a fact-to-fact join).

  REJECT propagation (transparency, not silent filtering): this model
  computes `severity` from two upstream REJECT sources but does NOT filter
  itself — every source row is still visible here for audit. The eventual
  EDW fact-loading model is responsible for WHERE severity = 'CONFIRMED'.
    - RG-02: this row's own (country, raw region) disagrees with the
      country's canonical region (e.g. Vietnam tagged AWR here, ESEAOR
      canonical) -> REJECT
    - MA-02: this row's member_association resolves to an org flagged
      REJECT (e.g. SFPA, multi-country) -> REJECT
*/

with base as (
    select
        source_row_number                                as response_key,
        funding,
        start_date,
        end_date,
        reporting_year,
        upper(trim(region))                              as raw_region_code,
        upper(trim(country))                             as raw_country_string,
        upper(trim(member_association))                  as ma_acronym,
        grant_usd,
        disasters_category,
        sub_category,
        proposed_people_reach,
        actual_people_reached,
        people_affected_alert,
        est_people_affected_alert,
        deliveries_conducted,
        clean_delivery_kits,
        dignity_hygiene_kits,
        cyps,
        unintended_pregnancies_averted,
        maternal_deaths_averted,
        trainings_conducted,
        source_file
    from {{ ref('stg_humanitarian_er') }}
),

country_lookup as (
    select normalized_key, iso_alpha3, country_name_display
    from {{ ref('int_country_resolved') }}
),

ma_lookup as (
    select ma_acronym, resolved_ma_key, severity as ma_severity
    from {{ ref('int_ma_uin_resolved') }}
    where ma_acronym is not null
),

region_conflict_lookup as (
    -- only the rows relevant to Humanitarian specifically
    select iso_alpha3, canonical_region_code, is_conflicting
    from {{ ref('int_country_region_assignment') }}
    where observed_source = 'HUMANITARIAN'
),

resolved as (
    select
        b.response_key,
        b.funding,
        b.start_date,
        b.end_date,
        b.reporting_year,
        c.iso_alpha3                                      as country_iso3,
        c.country_name_display,
        rc.canonical_region_code,
        m.resolved_ma_key,
        b.grant_usd,
        b.disasters_category,
        b.sub_category,
        b.proposed_people_reach,
        b.actual_people_reached,
        b.people_affected_alert,
        b.est_people_affected_alert,
        b.deliveries_conducted,
        b.clean_delivery_kits,
        b.dignity_hygiene_kits,
        b.cyps,
        b.unintended_pregnancies_averted,
        b.maternal_deaths_averted,
        b.trainings_conducted,
        b.source_file,
        coalesce(rc.is_conflicting, false)                as region_conflict,
        coalesce(m.ma_severity = 'REJECT', false)          as ma_conflict
    from base b
    left join country_lookup c
        on b.raw_country_string = c.normalized_key
    left join ma_lookup m
        on b.ma_acronym = m.ma_acronym
    left join region_conflict_lookup rc
        on c.iso_alpha3 = rc.iso_alpha3
)

select
    response_key,
    funding,
    start_date,
    end_date,
    reporting_year,
    country_iso3,
    country_name_display,
    canonical_region_code,
    resolved_ma_key,
    grant_usd,
    disasters_category,
    sub_category,
    proposed_people_reach,
    actual_people_reached,
    people_affected_alert,
    est_people_affected_alert,
    deliveries_conducted,
    clean_delivery_kits,
    dignity_hygiene_kits,
    cyps,
    unintended_pregnancies_averted,
    maternal_deaths_averted,
    trainings_conducted,
    source_file,
    case
        when region_conflict then 'REJECT'
        when ma_conflict     then 'REJECT'
        else 'CONFIRMED'
    end                                                    as severity,
    case
        when region_conflict then 'RG-02: region conflict for this country/source'
        when ma_conflict     then 'MA-02: member association flagged multi-country'
        else null
    end                                                    as review_note
from resolved
