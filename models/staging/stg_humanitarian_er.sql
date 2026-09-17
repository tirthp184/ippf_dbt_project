{{ config(materialized = 'view') }}

/*
  Mechanical cleanup only. The response_key assignment and the split into
  3 facts (response/service/gender-service) happens downstream in
  int_humanitarian_response.sql, int_humanitarian_service_unpivot.sql, and
  int_humanitarian_gender_service_unpivot.sql.
*/

select
    nullif(trim(funding), '')                              as funding,
    try_cast(trim(start_date) as date)                     as start_date,
    try_cast(trim(end_date) as date)                       as end_date,
    try_cast(trim(year) as number(4))                      as reporting_year,
    nullif(trim(region), '')                               as region,
    nullif(trim(country), '')                              as country,
    nullif(trim(member_association), '')                   as member_association,
    try_cast(trim(grant_usd) as number(18,2))              as grant_usd,
    nullif(trim(disasters_category), '')                   as disasters_category,
    nullif(trim(sub_category), '')                         as sub_category,
    try_cast(trim(proposed_people_reach) as number(18,0))  as proposed_people_reach,
    try_cast(trim(actual_people_reached) as number(18,0))  as actual_people_reached,
    try_cast(trim(fp_services) as number(18,0))            as fp_services,
    try_cast(trim(obst_services) as number(18,0))          as obst_services,
    try_cast(trim(gynaec_services) as number(18,0))        as gynaec_services,
    try_cast(trim(hiv_aids_services) as number(18,0))      as hiv_aids_services,
    try_cast(trim(sti_services) as number(18,0))           as sti_services,
    try_cast(trim(sgbv_specialised_services) as number(18,0)) as sgbv_specialised_services,
    try_cast(trim(comprehensive_abortion_care) as number(18,0)) as comprehensive_abortion_care,
    try_cast(trim(paediatric_services) as number(18,0))    as paediatric_services,
    try_cast(trim(fertility_services) as number(18,0))     as fertility_services,
    try_cast(trim(urology_services) as number(18,0))       as urology_services,
    try_cast(trim(srh_services) as number(18,0))           as srh_services,
    try_cast(trim(non_srh_services) as number(18,0))       as non_srh_services,
    try_cast(trim(deliveries_conducted) as number(18,0))   as deliveries_conducted,
    try_cast(trim(clean_delivery_kits) as number(18,0))    as clean_delivery_kits,
    try_cast(trim(dignity_hygiene_kits) as number(18,0))   as dignity_hygiene_kits,
    try_cast(trim(male_clinical_services) as number(18,0)) as male_clinical_services,
    try_cast(trim(female_clinical_services) as number(18,0)) as female_clinical_services,
    try_cast(trim(nonbinary_clinical_services) as number(18,0)) as nonbinary_clinical_services,
    try_cast(trim(male_awareness_session) as number(18,0)) as male_awareness_session,
    try_cast(trim(female_awareness_session) as number(18,0)) as female_awareness_session,
    try_cast(trim(nonbinary_awareness_session) as number(18,0)) as nonbinary_awareness_session,
    try_cast(trim(awareness_session_clients) as number(18,0)) as awareness_session_clients,
    try_cast(trim(trainings_conducted) as number(18,0))    as trainings_conducted,
    try_cast(trim(cyps) as number(18,2))                   as cyps,
    try_cast(trim(unintended_pregnancies_averted) as number(18,0)) as unintended_pregnancies_averted,
    try_cast(trim(maternal_deaths_averted) as number(18,0)) as maternal_deaths_averted,
    try_cast(trim(people_affected_alert) as number(18,0))  as people_affected_alert,
    try_cast(trim(est_people_affected_alert) as number(18,0)) as est_people_affected_alert,
    source_file,
    source_sheet,
    source_row_number,
    load_batch_id,
    load_ts
from {{ source('raw', 'raw_humanitarian_er') }}
