{{ config(materialized = 'view') }}
/* MA income by source + self-sufficiency ratio. Previously NO semantic
   coverage, despite the RFP's explicit interest in funding allocation and
   resource efficiency. self_sufficiency_ratio = locally generated income as
   a share of total income — a key federation health indicator. */
select
    d.calendar_year,
    maf.region_name, maf.ma_uin, maf.affiliate_name, maf.has_business_plan,
    sum(f.ippf_income)                as ippf_income,
    sum(f.intl_income_non_ippf)       as intl_income_non_ippf,
    sum(f.locally_generated_income)   as locally_generated_income,
    sum(coalesce(f.ippf_income,0) + coalesce(f.intl_income_non_ippf,0)
        + coalesce(f.locally_generated_income,0))                      as total_income,
    div0(sum(f.locally_generated_income),
         nullif(sum(coalesce(f.ippf_income,0) + coalesce(f.intl_income_non_ippf,0)
                    + coalesce(f.locally_generated_income,0)),0))      as self_sufficiency_ratio,
    div0(sum(f.ippf_income),
         nullif(sum(coalesce(f.ippf_income,0) + coalesce(f.intl_income_non_ippf,0)
                    + coalesce(f.locally_generated_income,0)),0))      as ippf_dependency_ratio
from {{ ref('fact_ma_income') }} f
join {{ ref('dim_date') }} d          on f.date_key = d.date_key
join {{ ref('v_dim_ma_flat') }} maf   on f.ma_key = maf.ma_key
group by 1,2,3,4,5
