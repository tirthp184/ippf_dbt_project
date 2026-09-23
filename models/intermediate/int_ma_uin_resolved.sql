{{
  config(
    materialized = 'table'
  )
}}

/*
  MA identity resolution — locked logic:
    0. RESOLUTION_DECISIONS (decision_type='MA_HOME_COUNTRY') -> a steward
       has confirmed which single country a multi-country-flagged acronym
       (MA-02) actually belongs to. Overrides the REJECT below, whatever
       acronym_country_span says.
    1. BP rows match on entity_code_num (the number in "CFPA (303)") — the
       most stable key available (verified zero drift across all 4 years).
    2. Humanitarian/Training rows match on normalized acronym. Verified: all
       9 MAs appearing in both BP and Humanitarian share the EXACT acronym,
       so exact match is the primary link — fuzzy is a safety net only, for
       genuinely new/variant keys, not a workhorse for existing overlaps.
    3. New natural key, no match >=90% fuzzy -> new organization (gets a real
       UIN string assigned later, in dim_member_association's incremental
       MERGE — NOT here, since this is a view and can't guarantee stable
       sequential numbering across runs).
    4. MA-02: same acronym tied to >1 distinct country (e.g. SFPA -> Sudan,
       Syria) -> REJECT. No confident single home country -> quarantined,
       not linked to any resolved organization. Resolvable via decision 0.
    5. MA-03/manual: IPPF (Secretariat) is NOT run through matching at all —
       it's a deliberate one-time onboarding, reserved UIN 'IPPF-MA-0000',
       org_type='Secretariat', match_method='MANUAL'. All 18 of its rows are
       admitted (see Exception Register MA-03 resolution).

  Output grain: one row per RESOLVED ORGANIZATION (natural keys that refer to
  the same real-world org are already merged here) — NOT one row per source
  observation. resolved_ma_key is the stable business key dim_member_
  association will MERGE on:
    - entity_code_num, if the org has a Business Plan presence
    - the acronym itself, if Humanitarian/Training-only
    - the literal 'IPPF' for the manual Secretariat entry
*/

with ma_country_decisions as (
    select upper(trim(raw_key)) as ma_acronym, resolved_value as decided_country_iso3, notes
    from {{ target.database }}.STG.RESOLUTION_DECISIONS
    where decision_type = 'MA_HOME_COUNTRY' and is_active
    qualify row_number() over (partition by upper(trim(raw_key)) order by decided_at desc) = 1
),

bp_raw as (
    select
        upper(trim(split_part(entity_code, '(', 1)))          as ma_acronym,
        regexp_substr(entity_code, '[0-9]+')                   as entity_code_num,
        affiliate_name,
        organisation_name_en,
        upper(trim(country_of_operation))                      as raw_country_string,
        primary_contact,
        contact_email,
        year
    from {{ source('raw', 'raw_membership_details') }}
    where entity_code is not null
),

-- One row per distinct BP entity (entity_code_num verified stable across
-- all 4 years — take the most recent year's descriptive attributes).
bp_entities as (
    select
        entity_code_num,
        ma_acronym,
        affiliate_name,
        organisation_name_en,
        raw_country_string,
        primary_contact,
        contact_email
    from bp_raw
    qualify row_number() over (
        partition by entity_code_num
        order by year desc
    ) = 1
),

country_resolved as (
    select normalized_key, iso_alpha3
    from {{ ref('int_country_resolved') }}
),

bp_entities_resolved as (
    select
        b.entity_code_num,
        b.ma_acronym,
        b.affiliate_name,
        b.organisation_name_en,
        c.iso_alpha3                                            as home_country_iso3,
        b.primary_contact,
        b.contact_email
    from bp_entities b
    left join country_resolved c
        on b.raw_country_string = c.normalized_key
),

-- Humanitarian + Training acronym observations (IPPF excluded — manual path)
hum_observations as (
    select
        'HUMANITARIAN'                            as source_system,
        upper(trim(member_association))            as ma_acronym,
        upper(trim(country))                       as raw_country_string
    from {{ source('raw', 'raw_humanitarian_er') }}
    where member_association is not null
      and upper(trim(member_association)) <> 'IPPF'
),

training_observations as (
    select
        'TRAINING'                                  as source_system,
        upper(trim(member_association))              as ma_acronym,
        upper(trim(country))                         as raw_country_string
    from {{ source('raw', 'raw_humanitarian_training') }}
    where member_association is not null
      and upper(trim(member_association)) <> 'IPPF'
),

non_bp_observations as (
    select * from hum_observations
    union all
    select * from training_observations
),

non_bp_observations_resolved as (
    select
        o.source_system,
        o.ma_acronym,
        c.iso_alpha3 as raw_country_iso3
    from non_bp_observations o
    left join country_resolved c
        on o.raw_country_string = c.normalized_key
),

-- MA-02 check: does this acronym's observations span more than one country?
-- (checked across ALL its appearances — Humanitarian/Training, and BP's own
-- country if the acronym also has a BP entity, for completeness)
acronym_country_span as (
    select
        ma_acronym,
        count(distinct raw_country_iso3) as distinct_country_count,
        listagg(distinct raw_country_iso3, ', ') within group (order by raw_country_iso3) as countries_seen
    from non_bp_observations_resolved
    where raw_country_iso3 is not null
    group by ma_acronym
),

-- Distinct non-BP acronyms, with their linkage attempt against BP.
non_bp_acronyms as (
    select distinct
        ma_acronym,
        listagg(distinct source_system, ',') within group (order by source_system) as source_systems
    from non_bp_observations_resolved
    group by ma_acronym
),

-- Step 1: exact acronym match to a BP entity (verified: all 9 real overlaps
-- match this way — no fuzzy matching needed for today's data).
linked_exact as (
    select
        n.ma_acronym,
        n.source_systems,
        b.entity_code_num,
        'DETERMINISTIC' as match_method,
        null::number as match_confidence
    from non_bp_acronyms n
    inner join bp_entities_resolved b
        on n.ma_acronym = b.ma_acronym
),

-- Step 2: fuzzy safety net for non-BP acronyms that did NOT exactly match —
-- catches a genuine spelling variant of an existing BP org.
unmatched_acronyms as (
    select n.ma_acronym, n.source_systems
    from non_bp_acronyms n
    where n.ma_acronym not in (select ma_acronym from linked_exact)
),

fuzzy_candidates as (
    select
        u.ma_acronym,
        u.source_systems,
        b.entity_code_num,
        jarowinkler_similarity(u.ma_acronym, b.ma_acronym) as match_confidence
    from unmatched_acronyms u
    cross join bp_entities_resolved b
),

linked_fuzzy as (
    select
        ma_acronym,
        source_systems,
        entity_code_num,
        'FUZZY' as match_method,
        match_confidence
    from fuzzy_candidates
    qualify row_number() over (partition by ma_acronym order by match_confidence desc) = 1
       and match_confidence >= 90
),

-- Step 3: genuinely new organizations — no BP link at all (expected: the 28
-- Humanitarian-only MAs identified earlier).
new_orgs as (
    select
        n.ma_acronym,
        n.source_systems
    from non_bp_acronyms n
    where n.ma_acronym not in (select ma_acronym from linked_exact)
      and n.ma_acronym not in (select ma_acronym from linked_fuzzy)
),

-- ---- Assemble the three resolved-organization populations ----

-- Population A: BP entities (with or without a linked Humanitarian/Training acronym)
resolved_bp as (
    select
        b.entity_code_num                                      as resolved_ma_key,
        b.entity_code_num,
        b.ma_acronym,
        b.affiliate_name,
        b.organisation_name_en,
        b.home_country_iso3,
        'Member Association'                                   as org_type,
        true                                                    as has_business_plan,
        'BP' || coalesce(',' || l.source_systems, '')          as source_systems,
        coalesce(l.match_method, 'DETERMINISTIC')               as match_method,
        l.match_confidence,
        'CONFIRMED'                                             as match_status,
        'CONFIRMED'                                             as severity,
        null                                                    as review_note
    from bp_entities_resolved b
    left join (
        select * from linked_exact
        union all
        select * from linked_fuzzy
    ) l
        on b.entity_code_num = l.entity_code_num
),

-- Population B: Humanitarian/Training-only new organizations (no BP link)
resolved_new as (
    select
        n.ma_acronym                                            as resolved_ma_key,
        null                                                     as entity_code_num,
        n.ma_acronym,
        null                                                     as affiliate_name,
        null                                                     as organisation_name_en,
        coalesce(dec.decided_country_iso3, acs.countries_seen)   as home_country_iso3,
        'Member Association'                                     as org_type,
        false                                                     as has_business_plan,
        n.source_systems,
        case when dec.ma_acronym is not null then 'HUMAN_DECISION' else 'NONE' end as match_method,
        null::number                                              as match_confidence,
        case
            when dec.ma_acronym is not null then 'CONFIRMED'
            when acs.distinct_country_count > 1 then 'NEEDS_REVIEW'
            else 'CONFIRMED'
        end as match_status,
        case
            when dec.ma_acronym is not null then 'CONFIRMED'
            when acs.distinct_country_count > 1 then 'REJECT'
            else 'CONFIRMED'
        end as severity,
        case
            when dec.ma_acronym is not null
                 then 'MA-02 resolved via steward decision: ' || coalesce(dec.notes, dec.decided_country_iso3)
            when acs.distinct_country_count > 1
                 then n.ma_acronym || ' spans ' || acs.distinct_country_count || ' countries: ' || acs.countries_seen
            else null
        end as review_note
    from new_orgs n
    left join acronym_country_span acs
        on n.ma_acronym = acs.ma_acronym
    left join ma_country_decisions dec
        on n.ma_acronym = dec.ma_acronym
),

-- Population C: IPPF Secretariat — manual onboarding, reserved UIN, never
-- passes through matching logic at all.
resolved_ippf as (
    select
        'IPPF'              as resolved_ma_key,
        null                as entity_code_num,
        'IPPF'              as ma_acronym,
        'International Planned Parenthood Federation (Secretariat)' as affiliate_name,
        null                as organisation_name_en,
        null                as home_country_iso3,
        'Secretariat'       as org_type,
        false               as has_business_plan,
        'TRAINING'          as source_systems,
        'MANUAL'            as match_method,
        null::number        as match_confidence,
        'CONFIRMED'         as match_status,
        'CONFIRMED'         as severity,
        null                as review_note
)

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
    match_status,
    severity,
    review_note
from resolved_bp

union all

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
    match_status,
    severity,
    review_note
from resolved_new

union all

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
    match_status,
    severity,
    review_note
from resolved_ippf