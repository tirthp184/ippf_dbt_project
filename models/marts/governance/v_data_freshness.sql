{{ config(materialized = 'view', schema = 'semantic') }}
/*
  Answers "when was this last synced" using timestamps already captured on
  every row (RAW.load_ts from ingestion, EDW fact.load_ts from the dbt build)
  -- no new tracking mechanism needed, just surfaced in one place.
*/

with raw_freshness as (
    select 'RAW - Membership Details' as layer, max(load_ts) as last_synced, count(*) as row_count
    from {{ source('raw','raw_membership_details') }}
    union all
    select 'RAW - Budget Focus Area', max(load_ts), count(*) from {{ source('raw','raw_budget_focus_area') }}
    union all
    select 'RAW - Budget Expense', max(load_ts), count(*) from {{ source('raw','raw_budget_expense') }}
    union all
    select 'RAW - Total Income', max(load_ts), count(*) from {{ source('raw','raw_total_income') }}
    union all
    select 'RAW - DHIS SRH Service', max(load_ts), count(*) from {{ source('raw','raw_dhis_srh_service') }}
    union all
    select 'RAW - DHIS CYP', max(load_ts), count(*) from {{ source('raw','raw_dhis_cyp') }}
    union all
    select 'RAW - DHIS Clients Totals', max(load_ts), count(*) from {{ source('raw','raw_dhis_clients_totals') }}
    union all
    select 'RAW - Humanitarian ER', max(load_ts), count(*) from {{ source('raw','raw_humanitarian_er') }}
    union all
    select 'RAW - Humanitarian Training', max(load_ts), count(*) from {{ source('raw','raw_humanitarian_training') }}
),

edw_freshness as (
    select 'EDW - Budget Focus Area' as layer, max(load_ts) as last_synced, count(*) as row_count
    from {{ ref('fact_budget_focus_area') }}
    union all
    select 'EDW - Budget Expense', max(load_ts), count(*) from {{ ref('fact_budget_expense') }}
    union all
    select 'EDW - MA Income', max(load_ts), count(*) from {{ ref('fact_ma_income') }}
    union all
    select 'EDW - DHIS Service', max(load_ts), count(*) from {{ ref('fact_dhis_service') }}
    union all
    select 'EDW - DHIS CYP', max(load_ts), count(*) from {{ ref('fact_dhis_cyp') }}
    union all
    select 'EDW - Client Profile', max(load_ts), count(*) from {{ ref('fact_client_profile') }}
    union all
    select 'EDW - Humanitarian Response', max(load_ts), count(*) from {{ ref('fact_hum_response') }}
    union all
    select 'EDW - Humanitarian Training', max(load_ts), count(*) from {{ ref('fact_hum_training') }}
)

select layer, last_synced, row_count,
       datediff('hour', last_synced, current_timestamp()) as hours_since_sync
from raw_freshness
union all
select layer, last_synced, row_count,
       datediff('hour', last_synced, current_timestamp())
from edw_freshness
order by layer
