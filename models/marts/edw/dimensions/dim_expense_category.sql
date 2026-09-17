{{ config(materialized = 'table') }}

/* Expense category pulled live from source, is_commodity computed inline
   (drives the stock-out supply-execution proxy). No seed. */

with src as (
    select distinct expense_category
    from {{ ref('stg_budget_expense') }}
    where expense_category is not null
)

select
    row_number() over (order by expense_category) as expense_category_key,
    expense_category as expense_category_name,
    (expense_category = 'Commodities') as is_commodity
from src

union all
select -1, 'Unknown / Unresolved', null
