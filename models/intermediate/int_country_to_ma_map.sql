{{ config(materialized = 'view') }}

/*
  Country -> MA lookup, needed because DHIS carries no MA field at all —
  only country. Verified earlier: country<->MA is strictly 1:1 within
  ESEAOR/SAR (the only regions DHIS covers). Derived from BP entities
  (has_business_plan = true), keyed on home_country_iso3.

  DH-01: 6 DHIS countries (Cambodia, Hong Kong, DPRK, Laos, Marshall Islands,
  Republic of Korea) have no BP-listed MA at all — they resolve to no row
  here, and downstream models route them to the Unknown MA member + WARN,
  per the exception register.

  The qualify below is a safety net, not expected to fire: if a future data
  load ever produces >1 MA per country (breaking the verified 1:1
  assumption), this arbitrarily picks one — see int_all_exceptions for the
  check that surfaces this break rather than letting it pass silently.
*/

with bp_entities as (
    select
        home_country_iso3,
        resolved_ma_key
    from {{ ref('int_ma_uin_resolved') }}
    where has_business_plan = true
      and home_country_iso3 is not null
)

select
    b.home_country_iso3,
    b.resolved_ma_key
from bp_entities b
qualify row_number() over (
    partition by b.home_country_iso3
    order by b.resolved_ma_key
) = 1

