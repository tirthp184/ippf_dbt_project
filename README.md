# IPPF Phase-3 POC — dbt Project

Transformation layer: RAW → STG → EDW → SEMANTIC, running as **dbt Projects on
Snowflake** (native, Git-connected, executes on Snowflake's own compute).

## Status

**Scaffolded, not yet fully built.** This commit contains:
- Full project config (`dbt_project.yml`, `packages.yml`)
- Source declarations for all 9 RAW tables (`models/staging/_sources.yml`)
- All 6 finalized seeds (see `seeds/`)
- Folder structure for staging / intermediate / marts (edw + semantic + governance)

**Not yet built:** the actual `stg_*`, `int_*`, `dim_*`, `fact_*`, semantic view,
and governance model `.sql` files. These come next.

## Seeds (`seeds/`)

Only genuine, non-derivable reference data lives here — anything that can be
computed from source data via a rule (e.g. focus area / expense category /
disaster flags) is inline SQL in the relevant model instead, not a seed.

| Seed | Rows | Purpose |
|---|---|---|
| `seed_country_override.csv` | 19 | Deterministic country fixes that must resolve BEFORE fuzzy ISO matching (confusables like Niger/Nigeria, oddities like DRC/Cape Verde/Lao PDR) |
| `seed_region_canonical.csv` | 6 | IPPF's 6 fixed regions — codes + full names (names aren't derivable from data) |
| `seed_training_topic.csv` | 19 | Training topics + safeguarding/youth flags (no keyword rule connects e.g. "GBV Fundamentals" to "safeguarding") |
| `seed_service_type.csv` | 15 | DHIS SRH metrics conformed to Humanitarian service equivalents (cross-domain naming, not string-matchable) |
| `seed_contraceptive_method.csv` | 12 | DHIS CYP methods classified LARC/SARC/Permanent/Barrier (clinical classification) |
| `seed_user_access.csv` | 6 | Demo RBAC users for the POC access-control scenario (production would sync from IPPF's identity system) |

## Resolution logic — locked design decisions

These govern the `int_*` models about to be built. See the project chat log /
`IPPF_Exception_Management_Register.md` for full detail and evidence.

**UIN (Member Association identity):**
1. BP rows match on `entity_code_num` (the number in `CFPA (303)`)
2. Humanitarian/Training rows match on normalized acronym
3. New key, no match ≥90% fuzzy → new UIN created
4. `SFPA` (Sudan/Syria multi-country conflict) → **REJECT**, quarantined
5. `IPPF` (Secretariat) → manually onboarded, reserved UIN `IPPF-MA-0000`, `org_type='Secretariat'`, `match_method='MANUAL'`

**Country (→ ISO 3166):**
1. `seed_country_override.csv` (deterministic, guards confusables)
2. Exact ISO match
3. Fuzzy match ≥90%
4. No match → auto-create placeholder (dedup on normalized string), `NEEDS_REVIEW`

**Region:**
1. Exact match against the 6 canonical codes first
2. Only if no exact match: strip trailing "O", retry
3. No match → Unknown (-1), `NEEDS_REVIEW` — **never auto-create a 7th region**

**Country → Region assignment:**
- Source precedence: Business Plan > DHIS2 > Humanitarian > Training
- First source (by precedence) sets the canonical region
- A later, disagreeing source → conflict logged; **REJECT** the conflicting rows only (e.g. Vietnam: BP/DHIS say ESEAOR, one Humanitarian row says AWR — the AWR row is quarantined, BP/DHIS Vietnam data loads normally)

**Duplicates:**
- Grain duplicates (same key, different values — "G1") → SUM aggregate, record `src_line_count`
- Reload duplicates → idempotent load (delete-then-insert per `source_file`, already implemented in the RAW ingestion script)
- Exact duplicate rows → **out of scope for the POC** (documented, not silently ignored — see exception register)

## Exception severities

REJECT (quarantined, not loaded) / WARN (loaded + flagged) / INFO (loaded,
recorded) / FILTERED (expected non-data, e.g. DHIS blank separator rows).
Full register: `IPPF_Exception_Management_Register.md`.

## Materialization strategy

- **Identity dims + bridges** (`dim_member_association`, `dim_country`,
  `bridge_ma_source_map`, `bridge_country_region_assignment`, `dim_project`,
  `dim_funding`) → **incremental (MERGE)** — surrogate keys must survive
  re-runs, since facts store them.
- **Small static dims** (geography, service_type, focus_area, expense_category,
  disaster, gender, service_mode, training_topic, contraceptive_method) →
  full-refresh table — low risk given their size/stability.
- **Facts** → full-refresh, source-scoped.
- **Semantic layer** → views.
