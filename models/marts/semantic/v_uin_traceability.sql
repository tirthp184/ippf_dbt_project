{{ config(materialized = 'view') }}
/* UIN traceability: shows how each organization's identity resolves across
   every source system. This is the demo-ready answer to the RFP's core
   problem statement — replacing the manual Excel "Mapping Register" with a
   governed, queryable registry.

   Reading this view: one row per (organization, source system). An org
   appearing in 2+ sources demonstrates cross-source identity resolution —
   e.g. an MA known as entity_code '303' in the Business Plan and by its
   acronym in Humanitarian data resolves to ONE ma_uin here. */
select
    maf.ma_uin,
    maf.org_type,
    maf.affiliate_name,
    maf.ma_acronym,
    maf.home_country_name,
    maf.region_name,
    maf.has_business_plan,
    b.source_system,
    b.source_natural_key,
    b.match_method,
    b.match_confidence,
    b.match_status,
    count(*) over (partition by maf.ma_uin) as source_system_count
from {{ ref('bridge_ma_source_map') }} b
join {{ ref('v_dim_ma_flat') }} maf on b.ma_key = maf.ma_key
