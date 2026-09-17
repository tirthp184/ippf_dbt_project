{{ config(materialized = 'view') }}
/* Budget vs actual variance & utilisation by MA / focus area / year. */
select
    d.calendar_year,
    maf.region_name, maf.affiliate_name, maf.ma_uin,
    fa.focus_area_name, fa.strategic_priority_name, fa.is_advocacy, fa.is_youth_related,
    sum(f.budget_amount) as budget_amount,
    sum(f.actual_amount) as actual_amount,
    sum(f.actual_amount) - sum(f.budget_amount)                as variance_amount,
    div0(sum(f.actual_amount), nullif(sum(f.budget_amount),0)) as utilisation_ratio
from {{ ref('fact_budget_focus_area') }} f
join {{ ref('dim_date') }} d       on f.date_key = d.date_key
join {{ ref('v_dim_ma_flat') }} maf on f.ma_key = maf.ma_key
join {{ ref('dim_focus_area') }} fa on f.focus_area_key = fa.focus_area_key
group by 1,2,3,4,5,6,7,8
