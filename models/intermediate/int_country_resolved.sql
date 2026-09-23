{{
  config(
    materialized = 'table'
  )
}}

/*
  Country resolution — locked logic:
    0. RESOLUTION_DECISIONS -> a human steward has already confirmed this
       exact raw string via the conflict-resolution app. Takes precedence
       over everything below -- checked first, and anything resolved here
       is excluded from steps 1-4.
    1. seed_country_override.csv   -> deterministic (guards confusables like
                                       Niger/Nigeria, Republic of Korea/DPRK
                                       that fuzzy-matching gets WRONG; also
                                       covers known oddities: DRC, Cape Verde,
                                       Lao PDR)
    2. Exact match to ISO 3166 name (official or common)
    3. Fuzzy match >= 90% (JAROWINKLER_SIMILARITY) against ISO 3166
    4. No match at all -> auto-create a placeholder record, deduped on the
       normalized raw string (so repeats of the same bad string don't spawn
       multiple placeholders), flagged NEEDS_REVIEW. iso_alpha3 = NULL.

  iso_alpha3 is the real business key. country_name_display is what
  dashboards show (may differ from ISO's official name, e.g. "Cape Verde"
  vs ISO's "Cabo Verde") -- see seed_country_override for those overrides.
*/

with iso_reference as (
    select iso_alpha3, country_name_iso_official, country_name_common
    from {{ ref('seed_iso_country_reference') }}
),

overrides as (
    select
        upper(trim(source_country_string)) as raw_country_key,
        iso_alpha3,
        country_name_display,
        override_reason
    from {{ ref('seed_country_override') }}
),

decisions as (
    select upper(trim(raw_key)) as normalized_key, resolved_value as iso_alpha3
    from {{ target.database }}.STG.RESOLUTION_DECISIONS
    where decision_type = 'COUNTRY' and is_active
    qualify row_number() over (partition by upper(trim(raw_key)) order by decided_at desc) = 1
),

-- Every raw country string across all sources, in one shape.
-- DHIS was already unpivoted at ingestion (country is a real column in RAW),
-- so no reshaping needed here -- just pull distinct values.
raw_country_observations as (

    select distinct
        'DHIS_SRH'                          as source_system,
        country_name                        as raw_country_string
    from {{ source('raw', 'raw_dhis_srh_service') }}
    where country_name is not null

    union all

    select distinct
        'DHIS_CYP'                           as source_system,
        country_name                         as raw_country_string
    from {{ source('raw', 'raw_dhis_cyp') }}
    where country_name is not null

    union all

    select distinct
        'DHIS_CLIENTS'                        as source_system,
        country_name                          as raw_country_string
    from {{ source('raw', 'raw_dhis_clients_totals') }}
    where country_name is not null

    union all

    select distinct
        'BP'                                   as source_system,
        country_of_operation                   as raw_country_string
    from {{ source('raw', 'raw_membership_details') }}
    where country_of_operation is not null

    union all

    select distinct
        'HUMANITARIAN'                          as source_system,
        country                                 as raw_country_string
    from {{ source('raw', 'raw_humanitarian_er') }}
    where country is not null

    union all

    select distinct
        'TRAINING'                                as source_system,
        country                                   as raw_country_string
    from {{ source('raw', 'raw_humanitarian_training') }}
    where country is not null

),

-- Collapse to one row per DISTINCT raw string (regardless of which source(s)
-- produced it) -- resolution only needs to happen once per unique string.
distinct_raw_strings as (
    select
        raw_country_string,
        upper(trim(raw_country_string)) as normalized_key,
        listagg(distinct source_system, ',') as source_systems
    from raw_country_observations
    group by 1, 2
),

-- Step 0: a human has already confirmed this exact raw string via the app.
-- Takes precedence over everything below.
step0_decision as (
    select
        d.raw_country_string,
        d.normalized_key,
        d.source_systems,
        dec.iso_alpha3,
        coalesce(r.country_name_common, r.country_name_iso_official, d.raw_country_string) as country_name_display,
        'HUMAN_DECISION' as match_method,
        null::number as match_confidence,
        'CONFIRMED' as match_status
    from distinct_raw_strings d
    inner join decisions dec
        on d.normalized_key = dec.normalized_key
    left join iso_reference r
        on dec.iso_alpha3 = r.iso_alpha3
),

-- Step 1: deterministic override
step1_override as (
    select
        d.raw_country_string,
        d.normalized_key,
        d.source_systems,
        o.iso_alpha3,
        o.country_name_display,
        'OVERRIDE' as match_method,
        null::number as match_confidence,
        'CONFIRMED' as match_status
    from distinct_raw_strings d
    inner join overrides o
        on d.normalized_key = o.raw_country_key
    where d.normalized_key not in (select normalized_key from step0_decision)
),

-- Step 2: exact match to ISO (only for strings that didn't hit an override)
step2_exact as (
    select
        d.raw_country_string,
        d.normalized_key,
        d.source_systems,
        r.iso_alpha3,
        coalesce(r.country_name_common, r.country_name_iso_official) as country_name_display,
        'EXACT' as match_method,
        null::number as match_confidence,
        'CONFIRMED' as match_status
    from distinct_raw_strings d
    inner join iso_reference r
        on upper(d.raw_country_string) = upper(r.country_name_iso_official)
        or upper(d.raw_country_string) = upper(r.country_name_common)
    where d.normalized_key not in (select normalized_key from step0_decision)
      and d.normalized_key not in (select normalized_key from step1_override)
),

-- Step 3: fuzzy match >= 90 (only for strings that missed steps 1 and 2)
fuzzy_candidates as (
    select
        d.raw_country_string,
        d.normalized_key,
        d.source_systems,
        r.iso_alpha3,
        coalesce(r.country_name_common, r.country_name_iso_official) as country_name_display,
        jarowinkler_similarity(d.raw_country_string, r.country_name_iso_official) as sim_official,
        jarowinkler_similarity(d.raw_country_string, r.country_name_common)       as sim_common
    from distinct_raw_strings d
    cross join iso_reference r
    where d.normalized_key not in (select normalized_key from step0_decision)
      and d.normalized_key not in (select normalized_key from step1_override)
      and d.normalized_key not in (select normalized_key from step2_exact)
),

step3_fuzzy as (
    select
        raw_country_string,
        normalized_key,
        source_systems,
        iso_alpha3,
        country_name_display,
        'FUZZY' as match_method,
        greatest(sim_official, sim_common) as match_confidence,
        case when greatest(sim_official, sim_common) >= 90 then 'CONFIRMED' else 'NEEDS_REVIEW' end as match_status
    from fuzzy_candidates
    qualify row_number() over (
        partition by normalized_key
        order by greatest(sim_official, sim_common) desc
    ) = 1
),

-- Step 4: anything still unresolved (fuzzy < 90, or no ISO candidate at all)
-- becomes a placeholder -- one row per distinct normalized string, so a
-- repeated bad value never spawns duplicate placeholders.
step4_placeholder as (
    select
        raw_country_string,
        normalized_key,
        source_systems,
        null as iso_alpha3,
        raw_country_string as country_name_display,
        'NONE' as match_method,
        match_confidence,
        'NEEDS_REVIEW' as match_status
    from step3_fuzzy
    where match_status = 'NEEDS_REVIEW'
),

-- step3_fuzzy's CONFIRMED rows continue as normal fuzzy matches;
-- its NEEDS_REVIEW rows are superseded by step4_placeholder (same key,
-- kept as placeholder rather than a low-confidence ISO guess).
step3_confirmed_only as (
    select * from step3_fuzzy where match_status = 'CONFIRMED'
)

select * from step0_decision
union all
select * from step1_override
union all
select * from step2_exact
union all
select * from step3_confirmed_only
union all
select * from step4_placeholder