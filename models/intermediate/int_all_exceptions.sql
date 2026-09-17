{{
  config(
    materialized = 'view'
  )
}}

/*
  Central exception union — every int_* model's flagged rows land here in one
  common shape. This is the single source V_DATA_QUALITY_REVIEW_QUEUE and
  STG.LOAD_EXCEPTIONS (governance layer) read from, rather than each model's
  review flags being queried separately.

  Add a new UNION ALL branch here every time a new int_ model produces
  WARN/REJECT/NEEDS_REVIEW rows (e.g. int_ma_uin_resolved's SFPA case,
  future fact-level FN and HU rules) -- this is the ONE place that changes.

  Common shape:
    exception_source   - which model/rule produced this
    exception_type     - the register ID where possible (CO-05, RG-02, MA-02...)
    subject             - the natural-language identifier of what's affected
    detail              - specifics (observed vs canonical, confidence, etc.)
    severity            - REJECT | WARN | INFO
    status              - CONFIRMED | NEEDS_REVIEW
    review_note
*/

with country_match_exceptions as (
    -- CO-05: countries that never resolved (override/exact/fuzzy all missed)
    select
        'int_country_resolved'                       as exception_source,
        'CO-05'                                       as exception_type,
        raw_country_string                            as subject,
        'match_method=' || match_method ||
            coalesce(', confidence=' || match_confidence::varchar, '') as detail,
        'WARN'                                        as severity,
        match_status                                  as status,
        'Country string did not resolve to a confirmed ISO match' as review_note
    from {{ ref('int_country_resolved') }}
    where match_status = 'NEEDS_REVIEW'
),

region_match_exceptions as (
    -- RG-03: region codes that didn't resolve (unknown, not just an "O" variant)
    select
        'int_region_resolved'                        as exception_source,
        'RG-03'                                        as exception_type,
        raw_region_code                                as subject,
        'source_system=' || source_system              as detail,
        'WARN'                                         as severity,
        match_status                                   as status,
        'Region code did not match any of the 6 canonical regions' as review_note
    from {{ ref('int_region_resolved') }}
    where match_status = 'NEEDS_REVIEW'
),

country_region_conflicts as (
    -- RG-02: country assigned conflicting regions across sources (e.g. Vietnam)
    select
        'int_country_region_assignment'               as exception_source,
        'RG-02'                                        as exception_type,
        country_name_display                           as subject,
        'observed=' || observed_source || ':' || observed_region_code ||
            ' vs canonical=' || canonical_region_code || ' (from ' || canonical_source || ')' as detail,
        severity,
        assignment_status                              as status,
        review_note
    from {{ ref('int_country_region_assignment') }}
    where is_conflicting = true
),

ma_multi_country_conflicts as (
    -- MA-02: same MA acronym tied to more than one country (e.g. SFPA -> Sudan, Syria)
    select
        'int_ma_uin_resolved'                          as exception_source,
        'MA-02'                                         as exception_type,
        resolved_ma_key                                 as subject,
        'org_type=' || org_type                         as detail,
        severity,
        match_status                                    as status,
        review_note
    from {{ ref('int_ma_uin_resolved') }}
    where severity = 'REJECT'
),

budget_amount_flags as (
    -- FN-02 (negative amount) and FN-03 (null amount, coalesced to 0) — both
    -- WARN, loaded as-is. Applies generically across both budget dedup models.
    select
        'int_budget_focus_area_dedup'                  as exception_source,
        case when has_negative_amount_flag then 'FN-02' else 'FN-03' end as exception_type,
        coalesce(resolved_ma_key, entity_code_num) || '/' || reporting_year
            || '/' || focus_area                        as subject,
        'src_line_count=' || src_line_count             as detail,
        'WARN'                                          as severity,
        'CONFIRMED'                                     as status,
        case
            when has_negative_amount_flag then 'Negative budget or actual amount in this grain'
            else 'Null/blank amount treated as 0 in aggregation'
        end                                              as review_note
    from {{ ref('int_budget_focus_area_dedup') }}
    where has_negative_amount_flag or has_null_amount_flag

    union all

    select
        'int_budget_expense_dedup'                     as exception_source,
        case when has_negative_amount_flag then 'FN-02' else 'FN-03' end as exception_type,
        coalesce(resolved_ma_key, entity_code_num) || '/' || reporting_year
            || '/' || expense_category                  as subject,
        'src_line_count=' || src_line_count             as detail,
        'WARN'                                          as severity,
        'CONFIRMED'                                     as status,
        case
            when has_negative_amount_flag then 'Negative budget or actual amount in this grain'
            else 'Null/blank amount treated as 0 in aggregation'
        end                                              as review_note
    from {{ ref('int_budget_expense_dedup') }}
    where has_negative_amount_flag or has_null_amount_flag
),

humanitarian_response_rejects as (
    -- RG-02 / MA-02 propagated to the actual fact rows they affect, plus
    -- HU-03 (reached > affected, logically impossible) and HU-04 (end before
    -- start) as hard REJECT checks specific to this fact.
    select
        'int_humanitarian_response'                    as exception_source,
        case
            when review_note like 'RG-02%' then 'RG-02'
            when review_note like 'MA-02%' then 'MA-02'
        end                                              as exception_type,
        'response_key=' || response_key                 as subject,
        review_note                                      as detail,
        severity,
        'CONFIRMED'                                      as status,
        review_note
    from {{ ref('int_humanitarian_response') }}
    where severity = 'REJECT'

    union all

    select
        'int_humanitarian_response'                    as exception_source,
        'HU-03'                                          as exception_type,
        'response_key=' || response_key                 as subject,
        'actual_people_reached=' || actual_people_reached ||
            ' > est_people_affected_alert=' || est_people_affected_alert as detail,
        'REJECT'                                         as severity,
        'CONFIRMED'                                      as status,
        'Actual people reached exceeds estimated people affected — logically impossible' as review_note
    from {{ ref('int_humanitarian_response') }}
    where est_people_affected_alert is not null
      and actual_people_reached > est_people_affected_alert

    union all

    select
        'int_humanitarian_response'                    as exception_source,
        'HU-04'                                          as exception_type,
        'response_key=' || response_key                 as subject,
        'start=' || start_date || ' end=' || end_date   as detail,
        'REJECT'                                         as severity,
        'CONFIRMED'                                      as status,
        'End date is before start date' as review_note
    from {{ ref('int_humanitarian_response') }}
    where start_date is not null
      and end_date is not null
      and end_date < start_date

    union all

    select
        'int_humanitarian_response'                    as exception_source,
        'HU-05'                                          as exception_type,
        'response_key=' || response_key                 as subject,
        'country_iso3=' || coalesce(country_iso3,'NULL') ||
            ' resolved_ma_key=' || coalesce(resolved_ma_key,'NULL') as detail,
        'REJECT'                                         as severity,
        'CONFIRMED'                                      as status,
        'Required key (country or member association) could not be resolved' as review_note
    from {{ ref('int_humanitarian_response') }}
    where country_iso3 is null
       or resolved_ma_key is null
),

dhis_unmapped_country as (
    -- DH-01: DHIS country has no BP-listed MA (expected: Cambodia, Hong Kong,
    -- DPRK, Laos, Marshall Islands, Republic of Korea)
    select distinct
        'int_dhis_service_conformed'                   as exception_source,
        'DH-01'                                          as exception_type,
        country_iso3                                     as subject,
        'no BP-linked MA for this country'              as detail,
        'WARN'                                           as severity,
        'CONFIRMED'                                      as status,
        'Routed to Unknown MA member — country has no Business Plan presence' as review_note
    from {{ ref('int_dhis_service_conformed') }}
    where resolved_ma_key is null
),

dhis_cyp_total_mismatch as (
    -- DH-02: CYP Total metric doesn't match the sum of individual methods
    -- for that country/year (verified 3 of 22 ESEAOR countries in 2024)
    select
        'int_dhis_cyp_conformed'                       as exception_source,
        'DH-02'                                          as exception_type,
        country_iso3 || '/' || reporting_year           as subject,
        'total=' || total_value || ' vs sum(methods)=' || summed_value as detail,
        'WARN'                                           as severity,
        'CONFIRMED'                                      as status,
        'CYP Total metric does not equal the sum of individual method values' as review_note
    from (
        select
            country_iso3,
            reporting_year,
            sum(iff(is_total_rollup, cyp_value, 0))     as total_value,
            sum(iff(not is_total_rollup, cyp_value, 0)) as summed_value
        from {{ ref('int_dhis_cyp_conformed') }}
        group by country_iso3, reporting_year
    )
    where abs(coalesce(total_value,0) - coalesce(summed_value,0)) > 1
),

ma_location_unmatched as (
    -- Illustrative MA location seed (27 rows) failed to name-match a real
    -- dim_member_association record. That MA's service point falls back to
    -- PLACEHOLDER coordinates (see dim_service_point) - flagged here so an
    -- unmatched reference name doesn't silently disappear.
    select
        'int_ma_location_matched'                      as exception_source,
        'GIS-01'                                         as exception_type,
        ma_name_reference                                as subject,
        'country_reference=' || country_reference       as detail,
        'WARN'                                           as severity,
        'NEEDS_REVIEW'                                   as status,
        'Illustrative location reference name did not match any Member Association record' as review_note
    from {{ ref('int_ma_location_matched') }}
    where match_status = 'NEEDS_REVIEW'
)

select * from country_match_exceptions
union all
select * from region_match_exceptions
union all
select * from country_region_conflicts
union all
select * from ma_multi_country_conflicts
union all
select * from budget_amount_flags
union all
select * from humanitarian_response_rejects
union all
select * from dhis_unmapped_country
union all
select * from dhis_cyp_total_mismatch
union all
select * from ma_location_unmatched