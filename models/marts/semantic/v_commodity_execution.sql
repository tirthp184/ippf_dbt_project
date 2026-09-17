{{ config(materialized = 'view') }}
/* Commodity budget vs actual execution ratio — supply/stock-out proxy. */
select
    d.calendar_year, maf.region_name, maf.affiliate_name,
    sum(f.budget_amount) as commodity_budget,
    sum(f.actual_amount) as commodity_actual,
    div0(sum(f.actual_amount), nullif(sum(f.budget_amount),0)) as execution_ratio
from {{ ref('fact_budget_expense') }} f
join {{ ref('dim_date') }} d              on f.date_key = d.date_key
join {{ ref('v_dim_ma_flat') }} maf        on f.ma_key = maf.ma_key
join {{ ref('dim_expense_category') }} ec  on f.expense_category_key = ec.expense_category_key
where ec.is_commodity = true
group by 1,2,3
