{{ config(materialized = 'incremental', unique_key = 'resolved_ma_key') }}

/*
  Incremental (MERGE) — this is THE model where int_ma_uin_resolved's
  business-key resolution finally becomes real, stable identifiers.
  TWO keys are generated here, both of which must survive re-runs:
    - ma_key: the numeric surrogate facts actually join on
    - ma_uin: the business-facing permanent identity string

    - MA-02 (SFPA, multi-country conflict): severity='REJECT' rows from
      int_ma_uin_resolved are EXCLUDED entirely — never get a UIN until the
      conflict is resolved.
    - IPPF (Secretariat): reserved 'IPPF-MA-0000' (never drawn from the
      sequential range), but still gets a normal sequential ma_key like any
      other row — only the business-facing UIN string is special-cased.
    - Every other new resolved_ma_key: next sequential ma_key AND next
      sequential IPPF-MA-#### number, both continuing from whatever's
      already been assigned (never reused/reshuffled for existing rows).

  POC SCOPE DECISION: insert-only for new keys on each run, no SCD
  attribute-versioning yet — this is what guarantees ma_key and ma_uin never
  shift for an org that already has one.
*/

with source_data as (
    select
        resolved_ma_key,
        entity_code_num,
        ma_acronym,
        affiliate_name,
        organisation_name_en,
        home_country_iso3,
        org_type,
        has_business_plan,
        source_systems,
        match_method,
        match_confidence,
        match_status
    from {{ ref('int_ma_uin_resolved') }}
    where severity != 'REJECT'   -- MA-02 (SFPA): excluded from the dimension entirely
),

country_lookup as (
    select country_key, iso_alpha3 from {{ ref('dim_country') }}
),

with_country_key as (
    select
        s.*,
        coalesce(c.country_key, -1) as home_country_key
    from source_data s
    left join country_lookup c
        on s.home_country_iso3 = c.iso_alpha3
),

new_rows as (
    select *
    from with_country_key
    {% if is_incremental() %}
    where resolved_ma_key not in (select resolved_ma_key from {{ this }})
    {% endif %}
),

{% if is_incremental() %}
max_existing as (
    select
        (select coalesce(max(ma_key), 0) from {{ this }}) as max_key,
        (select coalesce(max(try_cast(regexp_substr(ma_uin, '[0-9]+') as int)), 0)
            from {{ this }} where ma_uin <> 'IPPF-MA-0000') as max_num
),
{% else %}
max_existing as (select 0 as max_key, 0 as max_num),
{% endif %}

new_rows_keyed as (
    select
        n.*,
        m.max_key + row_number() over (order by n.resolved_ma_key) as ma_key
    from new_rows n
    cross join max_existing m
),

non_ippf_assigned as (
    select
        nk.*,
        'IPPF-MA-' || lpad(
            (m.max_num + row_number() over (order by nk.resolved_ma_key))::varchar, 4, '0'
        ) as ma_uin
    from new_rows_keyed nk
    cross join max_existing m
    where nk.resolved_ma_key <> 'IPPF'
),

ippf_assigned as (
    select
        nk.*,
        'IPPF-MA-0000' as ma_uin
    from new_rows_keyed nk
    where nk.resolved_ma_key = 'IPPF'
),

all_assigned as (
    select * from non_ippf_assigned
    union all
    select * from ippf_assigned
)

select
    ma_key,
    resolved_ma_key,
    ma_uin,
    org_type,
    entity_code_num,
    ma_acronym,
    affiliate_name,
    organisation_name_en,
    home_country_key,
    has_business_plan,
    source_systems,
    match_method,
    match_confidence,
    match_status,
    current_date()          as scd_valid_from,
    date '9999-12-31'       as scd_valid_to,
    true                    as scd_is_current
from all_assigned

{% if not is_incremental() %}
union all
select
    -1, '-1', 'IPPF-MA-UNKNOWN', 'Unknown', null, null, 'Unknown / Unresolved', null, -1,
    false, null, 'NONE', null, 'CONFIRMED',
    current_date(), date '9999-12-31', true
{% endif %}