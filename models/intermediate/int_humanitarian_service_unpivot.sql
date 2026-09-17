{{ config(materialized = 'view') }}

/*
  Detail stream #1 of the Humanitarian ER 3-way split. Grain: response event
  x service type. response_key is a DEGENERATE DIMENSION here (same
  source_row_number as int_humanitarian_response — no FK, just shared
  traceability).

  Maps each of the 12 Humanitarian service columns to its conformed
  service_type_name via seed_service_type.conforms_to_humanitarian — this is
  what lets DHIS's "S+R Contraceptive" and Humanitarian's "FP services" roll
  up together in the EDW fact (FACT_HUM_SERVICE / FACT_DHIS_SERVICE share
  DIM_SERVICE_TYPE).

  Uses native UNPIVOT since all 12 source columns are already NUMBER after
  staging cleanup.
*/

with base as (
    select
        source_row_number as response_key,
        fp_services,
        obst_services,
        gynaec_services,
        hiv_aids_services,
        sti_services,
        sgbv_specialised_services,
        comprehensive_abortion_care,
        paediatric_services,
        fertility_services,
        urology_services,
        srh_services,
        non_srh_services
    from {{ ref('stg_humanitarian_er') }}
),

unpivoted as (
    select
        response_key,
        service_col_name,
        service_count
    from base
    unpivot (
        service_count for service_col_name in (
            fp_services, obst_services, gynaec_services, hiv_aids_services,
            sti_services, sgbv_specialised_services, comprehensive_abortion_care,
            paediatric_services, fertility_services, urology_services,
            srh_services, non_srh_services
        )
    )
),

-- Translate the snake_case column alias to the exact label used in
-- seed_service_type.conforms_to_humanitarian.
column_to_label as (
    select
        response_key,
        service_count,
        case service_col_name
            when 'FP_SERVICES'                  then 'FP services'
            when 'OBST_SERVICES'                then 'Obst services'
            when 'GYNAEC_SERVICES'              then 'Gynaec. Services'
            when 'HIV_AIDS_SERVICES'            then 'HIV/AIDS services'
            when 'STI_SERVICES'                 then 'STI services'
            when 'SGBV_SPECIALISED_SERVICES'    then 'SGBV/Specialised services'
            when 'COMPREHENSIVE_ABORTION_CARE'  then 'Comprehensive abortion care services'
            when 'PAEDIATRIC_SERVICES'          then 'Paediatric services'
            when 'FERTILITY_SERVICES'           then 'Fertility services'
            when 'UROLOGY_SERVICES'             then 'Urology services'
            when 'SRH_SERVICES'                 then 'SRH services'
            when 'NON_SRH_SERVICES'             then 'non-SRH services'
        end as service_label
    from unpivoted
),

service_type_lookup as (
    select service_type_name, conforms_to_humanitarian
    from {{ ref('seed_service_type') }}
    where conforms_to_humanitarian is not null and conforms_to_humanitarian <> ''
)

select
    c.response_key,
    st.service_type_name,
    c.service_count
from column_to_label c
inner join service_type_lookup st
    on c.service_label = st.conforms_to_humanitarian
where c.service_count is not null
