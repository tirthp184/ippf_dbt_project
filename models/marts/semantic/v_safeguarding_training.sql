{{ config(materialized = 'view') }}
/* Safeguarding-related training effort (training side). */
select
    d.calendar_year, cf.region_name, cf.country_name_display,
    sum(t.training_count) as safeguarding_trainings,
    sum(t.people_trained) as people_trained_safeguarding
from {{ ref('fact_hum_training') }} t
join {{ ref('dim_date') }} d             on t.date_key = d.date_key
join {{ ref('v_dim_country_flat') }} cf  on t.country_key = cf.country_key
join {{ ref('dim_training_topic') }} tt  on t.training_topic_key = tt.training_topic_key
where tt.is_safeguarding = true
group by 1,2,3
