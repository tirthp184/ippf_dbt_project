{#
  Override dbt's default schema-naming behaviour.

  Default dbt behaviour concatenates the target schema and a model's custom
  +schema config as "<target_schema>_<custom_schema>" (e.g. EDW_STG). That
  would NOT match the fixed schema names already hardcoded throughout this
  project's DDL and semantic views (IPPF_EDW.RAW / STG / EDW / SEMANTIC /
  SEEDS). This macro makes a model's `+schema` config authoritative on its
  own, ignoring the profile's base schema, so `+schema: stg` in
  dbt_project.yml always resolves to exactly STG, not EDW_STG.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
