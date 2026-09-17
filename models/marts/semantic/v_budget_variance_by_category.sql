{{ config(materialized = 'view') }}
/* Budget vs actual variance & utilisation by MA / EXPENSE CATEGORY / year.
   Parallel to v_budget_variance (which is by focus area) — reads from the
   separate fact_budget_expense grain. The two views must NOT be joined:
   the same budget is split across focus areas AND across expense categories
   independently, so combining them double-counts. is_commodity is carried
   through since commodity execution is also the stock-out supply proxy. */
select
    d.calendar_year,
    maf.region_name, maf.affiliate_name, maf.ma_uin,
    ec.expense_category_name, ec.is_commodity,
    sum(f.budget_amount) as budget_amount,
    sum(f.actual_amount) as actual_amount,
    sum(f.actual_amount) - sum(f.budget_amount)                as variance_amount,
    div0(sum(f.actual_amount), nullif(sum(f.budget_amount),0)) as utilisation_ratio
from {{ ref('fact_budget_expense') }} f
join {{ ref('dim_date') }} d               on f.date_key = d.date_key
join {{ ref('v_dim_ma_flat') }} maf         on f.ma_key = maf.ma_key
join {{ ref('dim_expense_category') }} ec   on f.expense_category_key = ec.expense_category_key
group by 1,2,3,4,5,6
