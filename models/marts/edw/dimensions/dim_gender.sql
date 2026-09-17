{{ config(materialized = 'table') }}

/* Fixed gender values used by the Humanitarian gender-service unpivot. */

select 1 as gender_key, 'Male' as gender
union all select 2, 'Female'
union all select 3, 'Non-Binary'
union all select -1, 'Unknown / Unresolved'
