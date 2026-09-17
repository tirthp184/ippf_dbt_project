{{ config(materialized = 'view') }}

/*
  Detail stream #2 of the Humanitarian ER 3-way split. Grain: response event
  x gender x service mode. Same degenerate response_key pattern as the
  service unpivot — no FK to int_humanitarian_response.
*/

with base as (
    select
        source_row_number as response_key,
        male_clinical_services,
        female_clinical_services,
        nonbinary_clinical_services,
        male_awareness_session,
        female_awareness_session,
        nonbinary_awareness_session
    from {{ ref('stg_humanitarian_er') }}
),

unpivoted as (
    select
        response_key,
        col_name,
        service_count
    from base
    unpivot (
        service_count for col_name in (
            male_clinical_services, female_clinical_services, nonbinary_clinical_services,
            male_awareness_session, female_awareness_session, nonbinary_awareness_session
        )
    )
)

select
    response_key,
    case
        when col_name like 'MALE_%'      then 'Male'
        when col_name like 'FEMALE_%'    then 'Female'
        when col_name like 'NONBINARY_%' then 'Non-Binary'
    end                                                    as gender,
    case
        when col_name like '%CLINICAL_SERVICES'   then 'Clinical Service'
        when col_name like '%AWARENESS_SESSION'   then 'Awareness Session'
    end                                                    as service_mode,
    service_count
from unpivoted
where service_count is not null
