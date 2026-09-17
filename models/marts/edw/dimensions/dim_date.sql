{{ config(materialized = 'table') }}

/*
  Full day-grain calendar, generated natively via Snowflake's GENERATOR
  table function (no dbt_utils dependency — see packages.yml note on why
  that's currently empty). Range: 2020-01-01 to 2030-12-31 — safely covers
  all reporting years in the source data (2022-2025) plus the real day-grain
  start/end dates on Humanitarian responses, with headroom for near-future
  data.

  Dual-grain usage (locked decision): annual facts join on the year-end row
  (is_year_end = true); FACT_HUM_RESPONSE.start_date_key/end_date_key join
  on the actual calendar date.
*/

with date_spine as (
    select
        dateadd(day, seq4(), '2020-01-01'::date) as full_date
    from table(generator(rowcount => 4018))  -- 2020-01-01 through 2030-12-31 inclusive
)

select
    to_number(to_char(full_date, 'YYYYMMDD'))     as date_key,
    full_date,
    year(full_date)                                as calendar_year,
    quarter(full_date)                             as calendar_quarter,
    'Q' || quarter(full_date)                      as quarter_name,
    month(full_date)                               as month_number,
    monthname(full_date)                           as month_name,
    (month(full_date) = 12 and day(full_date) = 31) as is_year_end,
    year(full_date)                                as reporting_year
from date_spine
