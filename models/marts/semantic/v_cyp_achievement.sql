{{ config(materialized = 'view') }}
/* CYP (Couple Years of Protection) by method and clinical category.
   Previously NO semantic coverage. Method-availability change year-on-year
   is the stock-out/supply proxy discussed in the requirements analysis:
   a method dropping out of a country it previously served is a signal. */
select
    d.calendar_year,
    cf.region_name, cf.country_name_display, cf.iso_alpha3,
    maf.ma_uin, maf.affiliate_name,
    m.method_name, m.method_category, m.is_total_rollup,
    sum(f.cyp_value) as cyp_achieved
from {{ ref('fact_dhis_cyp') }} f
join {{ ref('dim_date') }} d                     on f.date_key = d.date_key
join {{ ref('v_dim_country_flat') }} cf          on f.country_key = cf.country_key
left join {{ ref('v_dim_ma_flat') }} maf         on f.ma_key = maf.ma_key
join {{ ref('dim_contraceptive_method') }} m     on f.method_key = m.method_key
group by 1,2,3,4,5,6,7,8,9
