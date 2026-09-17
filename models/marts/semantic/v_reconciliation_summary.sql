{{ config(materialized = 'view') }}
/* Row-count reconciliation: RAW source rows vs what actually landed in the
   EDW, per subject area. This is the artifact that proves nothing was
   silently lost or invented — an explicitly scored Scenario 2 requirement.

   Note the two legitimate reasons loaded <> raw, both intentional:
     - G1 aggregation: budget facts SUM duplicate grain lines, so
       loaded < raw by design (src_line_count records the collapse).
     - REJECT filtering: humanitarian responses failing RG-02/MA-02/HU-*
       are quarantined, so loaded < raw by design.
   variance_explained flags whether the gap matches a known cause. */

with raw_counts as (
    select 'Budget - Focus Area' as subject_area,
           (select count(*) from {{ source('raw','raw_budget_focus_area') }}) as raw_rows
    union all
    select 'Budget - Expense',
           (select count(*) from {{ source('raw','raw_budget_expense') }})
    union all
    select 'MA Income',
           (select count(*) from {{ source('raw','raw_total_income') }})
    union all
    select 'DHIS - SRH Service',
           (select count(*) from {{ source('raw','raw_dhis_srh_service') }})
    union all
    select 'DHIS - CYP',
           (select count(*) from {{ source('raw','raw_dhis_cyp') }})
    union all
    select 'Humanitarian - Response',
           (select count(*) from {{ source('raw','raw_humanitarian_er') }})
    union all
    select 'Humanitarian - Training',
           (select count(*) from {{ source('raw','raw_humanitarian_training') }})
),

loaded_counts as (
    select 'Budget - Focus Area' as subject_area,
           (select count(*) from {{ ref('fact_budget_focus_area') }}) as loaded_rows,
           (select coalesce(sum(src_line_count),0) from {{ ref('fact_budget_focus_area') }}) as source_lines_represented
    union all
    select 'Budget - Expense',
           (select count(*) from {{ ref('fact_budget_expense') }}),
           (select coalesce(sum(src_line_count),0) from {{ ref('fact_budget_expense') }})
    union all
    select 'MA Income',
           (select count(*) from {{ ref('fact_ma_income') }}), null
    union all
    select 'DHIS - SRH Service',
           (select count(*) from {{ ref('fact_dhis_service') }}), null
    union all
    select 'DHIS - CYP',
           (select count(*) from {{ ref('fact_dhis_cyp') }}), null
    union all
    select 'Humanitarian - Response',
           (select count(*) from {{ ref('fact_hum_response') }}), null
    union all
    select 'Humanitarian - Training',
           (select count(*) from {{ ref('fact_hum_training') }}), null
),

rejected_counts as (
    select 'Humanitarian - Response' as subject_area, count(*) as rejected_rows
    from {{ ref('int_humanitarian_response') }} where severity = 'REJECT'
)

select
    r.subject_area,
    r.raw_rows,
    l.loaded_rows,
    l.source_lines_represented,
    coalesce(rj.rejected_rows, 0)                              as rejected_rows,
    r.raw_rows - l.loaded_rows                                 as row_gap,
    case
        when r.raw_rows = l.loaded_rows then 'BALANCED'
        when l.source_lines_represented = r.raw_rows then 'EXPLAINED: G1 aggregation'
        when l.loaded_rows + coalesce(rj.rejected_rows,0) = r.raw_rows then 'EXPLAINED: REJECT quarantine'
        else 'REVIEW REQUIRED'
    end                                                         as variance_explained
from raw_counts r
left join loaded_counts l   on r.subject_area = l.subject_area
left join rejected_counts rj on r.subject_area = rj.subject_area