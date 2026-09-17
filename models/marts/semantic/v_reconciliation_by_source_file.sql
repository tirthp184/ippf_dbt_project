{{ config(materialized = 'view') }}
/*
  File-level reconciliation drill-down. Same purpose as v_reconciliation_summary
  but grouped by source_file within each subject area, so a completeness gap
  (e.g. SAR 2025) is visible against the specific file, not blended into an
  8-file subject-area total.

  Humanitarian Response/Training are each a single physical file, so their
  file-level rows are equivalent to the subject-area summary — included for
  structural completeness, not because they add granularity.
*/

with raw_counts as (
    select 'Budget - Focus Area' as subject_area, source_file, count(*) as raw_rows
    from {{ source('raw','raw_budget_focus_area') }} group by 1,2
    union all
    select 'Budget - Expense', source_file, count(*)
    from {{ source('raw','raw_budget_expense') }} group by 1,2
    union all
    select 'MA Income', source_file, count(*)
    from {{ source('raw','raw_total_income') }} group by 1,2
    union all
    select 'DHIS - SRH Service', source_file, count(*)
    from {{ source('raw','raw_dhis_srh_service') }} group by 1,2
    union all
    select 'DHIS - CYP', source_file, count(*)
    from {{ source('raw','raw_dhis_cyp') }} group by 1,2
    union all
    select 'DHIS - Clients Totals', source_file, count(*)
    from {{ source('raw','raw_dhis_clients_totals') }} group by 1,2
    union all
    select 'Humanitarian - Response', source_file, count(*)
    from {{ source('raw','raw_humanitarian_er') }} group by 1,2
    union all
    select 'Humanitarian - Training', source_file, count(*)
    from {{ source('raw','raw_humanitarian_training') }} group by 1,2
),

loaded_counts as (
    select 'Budget - Focus Area' as subject_area, source_file,
           count(*) as loaded_rows, coalesce(sum(src_line_count),0) as source_lines_represented
    from {{ ref('fact_budget_focus_area') }} group by 1,2
    union all
    select 'Budget - Expense', source_file, count(*), coalesce(sum(src_line_count),0)
    from {{ ref('fact_budget_expense') }} group by 1,2
    union all
    select 'MA Income', source_file, count(*), null
    from {{ ref('fact_ma_income') }} group by 1,2
    union all
    select 'DHIS - SRH Service', source_file, count(*), null
    from {{ ref('fact_dhis_service') }} group by 1,2
    union all
    select 'DHIS - CYP', source_file, count(*), null
    from {{ ref('fact_dhis_cyp') }} group by 1,2
    union all
    select 'DHIS - Clients Totals', source_file, count(*), null
    from {{ ref('fact_client_profile') }} group by 1,2
    union all
    select 'Humanitarian - Response', source_file, count(*), null
    from {{ ref('fact_hum_response') }} group by 1,2
    union all
    select 'Humanitarian - Training', source_file, count(*), null
    from {{ ref('fact_hum_training') }} group by 1,2
),

rejected_counts as (
    select 'Humanitarian - Response' as subject_area, r.source_file, count(*) as rejected_rows
    from {{ ref('int_humanitarian_response') }} r
    join {{ source('raw','raw_humanitarian_er') }} raw_er
        on r.response_key = raw_er.source_row_number
    where r.severity = 'REJECT'
    group by 1,2
)

select
    r.subject_area,
    r.source_file,
    r.raw_rows,
    l.loaded_rows,
    l.source_lines_represented,
    coalesce(rj.rejected_rows, 0)                              as rejected_rows,
    r.raw_rows - coalesce(l.loaded_rows,0)                     as row_gap,
    case
        when r.raw_rows = coalesce(l.loaded_rows,0) then 'BALANCED'
        when l.source_lines_represented = r.raw_rows then 'EXPLAINED: G1 aggregation'
        when coalesce(l.loaded_rows,0) + coalesce(rj.rejected_rows,0) = r.raw_rows then 'EXPLAINED: REJECT quarantine'
        -- DHIS Clients Totals is stored long (one row per metric) and pivoted
        -- to one wide row per Year x Country in fact_client_profile. A clean
        -- integer ratio here means every source row is represented, just
        -- reshaped into columns -- not a data loss.
        when r.subject_area = 'DHIS - Clients Totals'
             and l.loaded_rows > 0
             and mod(r.raw_rows, l.loaded_rows) = 0
            then 'EXPLAINED: pivot (' || (r.raw_rows / l.loaded_rows)::varchar || ' metrics per row)'
        else 'REVIEW REQUIRED'
    end                                                         as variance_explained
from raw_counts r
left join loaded_counts l    on r.subject_area = l.subject_area and r.source_file = l.source_file
left join rejected_counts rj on r.subject_area = rj.subject_area and r.source_file = rj.source_file
order by r.subject_area, r.source_file