{{ config(materialized = 'view') }}
/*
  Answers "what is the latest data we actually have" -- the newest reporting
  period covered by the DATA CONTENT itself, per source. This is distinct
  from v_ingestion_run_status / v_pipeline_run_status, which report on WHEN
  the pipeline last ran, not what period the data covers.

  Example of why this matters: the pipeline could run today, but if the
  latest DHIS file only contains 2025 data, "as of" for DHIS is 2025 -
  regardless of when the load happened.

  Grain: one row per subject area, showing the latest reporting_year
  (all subject areas) and, where the source carries real calendar dates
  (Humanitarian Response only), the latest actual date too.
*/

with year_coverage as (
    select 'Budget - Focus Area' as subject_area, max(reporting_year) as latest_year
    from {{ ref('fact_budget_focus_area') }}
    union all
    select 'Budget - Expense', max(reporting_year)
    from {{ ref('fact_budget_expense') }}
    union all
    select 'MA Income', max(reporting_year)
    from {{ ref('fact_ma_income') }}
    union all
    select 'DHIS - SRH Service', max(d.calendar_year)
    from {{ ref('fact_dhis_service') }} f
    join {{ ref('dim_date') }} d on f.date_key = d.date_key
    union all
    select 'DHIS - CYP', max(d.calendar_year)
    from {{ ref('fact_dhis_cyp') }} f
    join {{ ref('dim_date') }} d on f.date_key = d.date_key
    union all
    select 'DHIS - Client Profile', max(d.calendar_year)
    from {{ ref('fact_client_profile') }} f
    join {{ ref('dim_date') }} d on f.date_key = d.date_key
    union all
    select 'Humanitarian - Response', max(d.calendar_year)
    from {{ ref('fact_hum_response') }} f
    join {{ ref('dim_date') }} d on f.date_key = d.date_key
    union all
    select 'Humanitarian - Training', max(d.calendar_year)
    from {{ ref('fact_hum_training') }} f
    join {{ ref('dim_date') }} d on f.date_key = d.date_key
),

-- Humanitarian Response is the ONLY source with real day-grain dates
-- (actual response start/end dates, not just a reporting year) - shown
-- separately since it's a more precise "as of" than a year for this one case.
latest_actual_date as (
    select max(ed.full_date) as latest_response_end_date
    from {{ ref('fact_hum_response') }} f
    join {{ ref('dim_date') }} ed on f.end_date_key = ed.date_key
)

select
    y.subject_area,
    y.latest_year,
    case when y.subject_area = 'Humanitarian - Response'
         then (select latest_response_end_date from latest_actual_date)
         else null
    end as latest_actual_date,
    (select max(latest_year) from year_coverage) as overall_latest_year_any_source
from year_coverage y
order by y.subject_area
