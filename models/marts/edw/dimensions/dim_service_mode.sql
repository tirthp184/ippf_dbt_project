{{ config(materialized = 'table') }}

/* Fixed service-mode values used by the Humanitarian gender-service unpivot. */

select 1 as service_mode_key, 'Clinical Service' as service_mode
union all select 2, 'Awareness Session'
union all select -1, 'Unknown / Unresolved'
