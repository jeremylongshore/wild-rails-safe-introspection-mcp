# Planned v2 Tool Additions — wild-rails-safe-introspection-mcp

**Document type:** Planning
**Filed as:** `017-PP-PLAN-v2-tool-additions.md`
**Status:** Active — planning only, no v2 tools implemented
**Last updated:** 2026-03-18
**Epic:** 10 — Expansion Readiness
**Task:** 1cv.2 — Document the planned v2 tool additions with their safety review requirements

---

## 1. v1 Tool Baseline

The v1 server ships with three MCP tools, all read-only, all audited, all policy-enforced. These are the foundation that v2 builds on.

| Tool | Classification | Purpose |
|------|---------------|---------|
| `inspect_model_schema` | `schema_inspection` | Inspect column types and associations of an allowlisted model |
| `lookup_record_by_id` | `record_lookup` | Fetch a single record by primary key |
| `find_records_by_filter` | `filtered_lookup` | Find records matching a single field/value filter with row cap |

All three share: model allowlist gating, denylist column stripping, identity requirement, capability gate check, full audit recording. Response format is uniform: `{ status, ... }` wrapped in `MCP::Tool::Response` with a single JSON text block. Denied, errored, and timed-out invocations all produce audit records.

Cross-reference: [010 — Tool Catalog](010-DR-REFF-tool-catalog.md)

---

## 2. Planned v2 Tool Additions

Each candidate below is read-only, policy-enforced, and bounded. No v2 tool introduces write capability, dynamic code execution, or unbounded queries.

### 2.1 `find_records_by_compound_filter`

**Purpose:** Extend filtered record search with compound predicates (AND/OR combinations).

**Why v2, not v1:** v1's single-predicate filter was intentionally minimal to limit query complexity. Compound predicates increase the SQL surface area and require additional validation of logical operators and predicate depth.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `model_name` | string | yes | Rails model class name |
| `predicates` | array | yes | Array of `{ field, operator, value }` objects |
| `logic` | string | no | `"and"` (default) or `"or"` — top-level logical combinator |

**Constraints:**
- Maximum predicate count: configurable, default 5, hard ceiling 10
- Allowed operators: `eq`, `not_eq`, `lt`, `gt`, `lte`, `gte`, `in`, `not_in`, `null`, `not_null` — no `like`, no regex, no raw SQL fragments
- Each `field` must pass the same allowlist/denylist check as `find_records_by_filter`
- `in` / `not_in` value arrays capped at 100 elements
- Row cap and query timeout enforced identically to v1
- No nested predicate groups — one level of AND/OR only

**Safety classification:** `compound_filtered_lookup`

**What's new vs v1:** Multiple filter fields in one query. The SQL generation path must be validated to prevent operator injection (e.g., passing `"operator": "1=1 OR"` should produce a denial, not SQL injection). Predicate depth limiting prevents query bombs.

---

### 2.2 `traverse_association`

**Purpose:** Follow a single association hop from a known record to its related record(s).

**Why v2, not v1:** Association traversal introduces a second model into a single tool invocation. The safety implications include: ensuring both models are allowlisted, applying denylist stripping to both source and target, and preventing recursive traversal chains.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `model_name` | string | yes | Source model class name |
| `id` | string | yes | Source record primary key |
| `association_name` | string | yes | Rails association name (e.g., `"users"`, `"account"`) |

**Constraints:**
- Both source and target model must be on the allowlist
- Association must exist on the source model (validated against ActiveRecord reflection, not user input)
- Only `belongs_to`, `has_one`, and `has_many` associations supported — no `has_many :through` in v2 (this would require multi-hop traversal)
- For `has_many` associations: row cap enforced on the returned set
- For `belongs_to` / `has_one`: returns a single record (no row cap needed)
- Denylist column stripping applied to the target model's records
- No recursive traversal — one hop only, enforced at the tool handler level
- No chaining (the agent cannot call `traverse_association` on a result of `traverse_association` to simulate multi-hop — each call starts fresh from a known record ID)

**Safety classification:** `association_traversal`

**What's new vs v1:** Two-model scope within a single invocation. The query guard must validate both models. Audit records must capture both the source and target model. The association name must be validated against the actual model's reflection data — not resolved by `send` or dynamic dispatch on user input.

---

### 2.3 `list_available_models`

**Purpose:** List all models on the access allowlist with basic metadata.

**Why v2, not v1:** v1 required agents to know model names in advance. A discovery tool reduces friction for agents that need to understand what they can inspect. The risk is low — this exposes only what's already allowlisted — but it still requires safety review because it changes the information flow (agents learn the full accessible surface in one call).

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| (none) | — | — | No parameters required |

**Constraints:**
- Returns only models on the access allowlist — does not reveal non-allowlisted models
- For each model: name, table name, column count, association count
- Does not return column names or association details (use `inspect_model_schema` for that)
- Does not return record counts (would require queries against each table)
- Denylist-blocked models that are also on the allowlist: the denylist wins, they do not appear

**Safety classification:** `model_discovery`

**What's new vs v1:** No per-model parameter means no model-level allowlist check per call — the tool's scope IS the allowlist. The safety concern is information aggregation: an agent learns the entire accessible surface in one call. This is intentional (the information is already accessible via per-model calls), but the change in information flow should be documented.

---

## 3. Safety Review Requirements

Every v2 tool must pass the following checklist before it ships. This checklist is derived from the safety model ([003](003-TQ-STND-safety-model.md)), threat model ([005](005-AT-ADEC-threat-model.md)), and evaluation strategy ([011](011-TQ-SECU-evaluation-strategy.md)).

### 3.1 Per-Tool Safety Checklist

- [ ] **Read-only enforcement verified** — no write paths, no mutation SQL, no ActiveRecord write methods in the call chain
- [ ] **Allowlist check** — tool only operates on explicitly allowed models
- [ ] **Denylist check** — blocked columns stripped from all output; blocked models inaccessible
- [ ] **Row cap enforcement** — respects configurable limit (default 50, hard ceiling 1000)
- [ ] **Query timeout enforcement** — respects configurable limit (default 5s, hard ceiling 30s)
- [ ] **Identity required** — rejects unauthenticated callers before reaching the adapter
- [ ] **Capability gate check** — calls `CapabilityGate.permitted?` before execution
- [ ] **Audit trail** — produces an audit record for every outcome (success, denial, error, timeout)
- [ ] **Parameter safety** — no `eval`, no `constantize`, no `send`/`public_send` with user input, no SQL interpolation
- [ ] **Conservative defaults** — restrictive when uncertain; operators expand via config
- [ ] **Adversarial tests written** — tool-specific attack vectors from the threat model
- [ ] **Threat model review** — each of the 7 threats evaluated for the new tool (see Section 4)
- [ ] **Denial responses indistinguishable** — new tool's denials match existing denial format exactly
- [ ] **Tool delegates through `ToolHandler.execute`** — no direct adapter calls from the tool handler
- [ ] **Tool registered in `ServerFactory::TOOLS`** — fixed registration, no dynamic tool loading

### 3.2 Additional Checklist for `find_records_by_compound_filter`

- [ ] Operator whitelist enforced — only allowed operators accepted, all others denied
- [ ] Predicate count limit enforced — exceeding maximum produces denial, not truncation
- [ ] `in`/`not_in` value array size enforced
- [ ] No nested predicate groups — depth limited to one level
- [ ] SQL generation uses parameterized queries for all predicate values
- [ ] Operator values are resolved by exact string match, not interpolated into SQL

### 3.3 Additional Checklist for `traverse_association`

- [ ] Both source and target model validated against allowlist
- [ ] Association name validated against ActiveRecord reflection, not user input
- [ ] `has_many :through` associations rejected
- [ ] Recursive traversal impossible — no second hop from target records
- [ ] Audit record captures both source and target model names
- [ ] Denylist stripping applied to target model's columns

### 3.4 Additional Checklist for `list_available_models`

- [ ] Returns only allowlisted models (denylist-blocked models excluded even if on allowlist)
- [ ] Does not return column names, record counts, or association details
- [ ] Information aggregation risk documented and accepted

---

## 4. Threat Model Applicability Matrix

Each of the 7 threats from the threat model ([005](005-AT-ADEC-threat-model.md)) is evaluated per v2 tool candidate.

### Threat 1: Prompt Injection Through Tool Parameters

| Tool | Applicability | Notes |
|------|--------------|-------|
| `find_records_by_compound_filter` | **High** | Multiple parameters (`predicates` array, `operator`, `value`, `logic`) all need injection-safe handling. Operator field is new attack surface — must be resolved by exact match against a whitelist, never interpolated. |
| `traverse_association` | **Medium** | `association_name` is a new parameter type — must be validated against model reflection, not used for `send`/dynamic dispatch. Same injection risk as `model_name` for the source parameters. |
| `list_available_models` | **Low** | No user-provided parameters. No injection vector. |

### Threat 2: Credential Abuse and Unauthorized Access

| Tool | Applicability | Notes |
|------|--------------|-------|
| `find_records_by_compound_filter` | **Same as v1** | Same identity pipeline. No new credential surface. |
| `traverse_association` | **Same as v1** | Same identity pipeline. No new credential surface. |
| `list_available_models` | **Same as v1** | Same identity pipeline. Provides aggregate surface information but only for already-authorized callers. |

### Threat 3: Data Exfiltration Through Allowed Channels

| Tool | Applicability | Notes |
|------|--------------|-------|
| `find_records_by_compound_filter` | **Elevated** | Compound predicates allow more targeted data extraction than single-predicate search. An attacker can narrow queries to extract specific record sets efficiently. Mitigated by row caps, audit trail, and rate limiting (future). |
| `traverse_association` | **Elevated** | Association traversal lets an attacker map relationships between records, building a richer picture of the data graph. One-hop limit constrains depth but not breadth. Mitigated by per-hop row caps and audit trail. |
| `list_available_models` | **Low** | Reveals the accessible model surface but not record data. The information is already derivable by guessing model names with existing tools. |

### Threat 4: Query Abuse (Resource Exhaustion)

| Tool | Applicability | Notes |
|------|--------------|-------|
| `find_records_by_compound_filter` | **Elevated** | Compound predicates can produce more expensive queries than single predicates. OR-combined predicates on unindexed columns could trigger full table scans. Mitigated by query timeout, row cap, and predicate count limit. |
| `traverse_association` | **Medium** | Association queries may hit unindexed foreign keys. `has_many` associations on large tables could be expensive. Mitigated by query timeout and row cap. |
| `list_available_models` | **Low** | No database queries against record tables. Only reads from the in-memory policy configuration. |

### Threat 5: Model and Schema Enumeration

| Tool | Applicability | Notes |
|------|--------------|-------|
| `find_records_by_compound_filter` | **Same as v1** | Same denial response format. No additional enumeration surface. |
| `traverse_association` | **Slightly elevated** | Association name parameter could be used for enumeration — trying different association names to discover relationships. Mitigation: denial response for invalid associations must be indistinguishable from denial for non-allowlisted target models. |
| `list_available_models` | **N/A — intentional disclosure** | This tool deliberately reveals the allowlisted model surface. This is by design — it only shows what's already accessible. The tool does NOT reveal non-allowlisted models. |

### Threat 6: Audit Trail Tampering or Bypass

| Tool | Applicability | Notes |
|------|--------------|-------|
| `find_records_by_compound_filter` | **Same as v1** | Same audit pipeline. Predicate array must be captured in full in audit records. |
| `traverse_association` | **Same as v1** | Same audit pipeline. Must capture source model, target model, and association name. |
| `list_available_models` | **Same as v1** | Same audit pipeline. No special audit considerations. |

### Threat 7: Configuration Tampering

| Tool | Applicability | Notes |
|------|--------------|-------|
| `find_records_by_compound_filter` | **Same as v1** | Operator whitelist is code-defined (not configurable). Predicate limits are configurable — same tampering risk as row caps. |
| `traverse_association` | **Same as v1** | Association validation uses ActiveRecord reflection at runtime — not configurable, not tamperable through policy files. |
| `list_available_models` | **Same as v1** | Returns the loaded policy state. If the policy is tampered, this tool would reflect the tampered state — same risk as all other tools. |

---

## 5. What Is NOT v2

These are confirmed out-of-scope for v2. They are documented here to prevent scope creep and to establish clear boundaries for future planning.

**Write operations.** No create, update, delete, or mutation of any kind. The read-only constraint is a design invariant, not a version-gated feature. If writes are ever introduced, they belong in `wild-admin-tools-mcp`, not here.

**Arbitrary Ruby/Rails execution.** No tool that accepts Ruby code as input. No `eval`, no console emulation, no dynamic method dispatch on user input. This is a permanent boundary.

**Admin operations.** Running jobs, clearing caches, updating feature flags, managing users — all belong in `wild-admin-tools-mcp`. This repo reads; that repo acts.

**Analytics queries.** Aggregation, reporting, GROUP BY, window functions, cross-model joins for analytics purposes. The tools answer operational questions ("what is this record?"), not business intelligence questions ("how many users signed up last week?").

**Multi-hop association traversal.** v2 supports one hop only. Multi-hop traversal (`has_many :through`, recursive graph walking) dramatically increases the attack surface for data exfiltration and query abuse. If multi-hop is ever considered, it requires its own threat model review and a new set of safety controls (traversal depth limits, visited-set tracking, aggregate row caps across hops).

**Dynamic tool registration at runtime.** The tool set is fixed at startup. `ServerFactory::TOOLS` is a frozen array. No MCP client can register, modify, or remove tools during a session. This is a safety invariant.

**`has_many :through` associations.** Even for single-hop traversal, `has_many :through` is excluded from v2 because it implies an intermediate join table that may not be allowlisted. Supporting it safely requires validating all three models (source, through, target).

**Streaming or pagination.** v2 maintains the v1 approach: results beyond the row cap are truncated. Cursor-based pagination would be useful but requires stateful session management and introduces new attack vectors (cursor manipulation, session fixation).

Cross-reference: [001 — Blueprint, Section 5: Non-Goals](001-PP-PLAN-repo-blueprint.md)

---

## 6. Prerequisites for v2 Implementation

Before any v2 tool is implemented, ALL of the following must be true:

1. **All v1 safety tests pass** — the full 468+ test suite is green with 0 failures
2. **Capability gate integration is complete** — the real `wild-capability-gate` gem replaces the v1 stub (task 1cv.1 plan executed, tasks 1cv.3–1cv.4 completed)
3. **Each new tool gets its own sub-epic** — with dedicated adversarial testing, not added as an afterthought to an existing epic
4. **Evaluation strategy release checklist re-run** — the full checklist from [011](011-TQ-SECU-evaluation-strategy.md) must pass for each new tool, including the "new tool added" section
5. **Per-tool threat model review** — each tool's threat matrix row (Section 4 above) reviewed and signed off before implementation begins
6. **Adversarial tests written before production code** — the test-first approach from the evaluation strategy applies: write the attack, then write the defense
7. **Doc 010 (Tool Catalog) updated** — new tools documented in the same format as v1 tools before release
8. **No open safety-defect beads** — all known safety defects resolved before expanding the tool surface

---

## 7. Reference Documents

| Document | Relevance |
|----------|-----------|
| [003 — Safety Model](003-TQ-STND-safety-model.md) | Governing safety spec — all v2 tools must comply |
| [005 — Threat Model](005-AT-ADEC-threat-model.md) | 7 threats evaluated per v2 tool in Section 4 |
| [010 — Tool Catalog](010-DR-REFF-tool-catalog.md) | v1 tool definitions — format to mirror for v2 |
| [011 — Evaluation Strategy](011-TQ-SECU-evaluation-strategy.md) | Release checklist and new-tool evaluation protocol |
| [001 — Blueprint](001-PP-PLAN-repo-blueprint.md) | Mission and non-goals — v2 must stay within boundaries |
| [016 — Capability Gate Integration Plan](016-AT-ADEC-capability-gate-integration-plan.md) | Prerequisite: gate integration must complete before v2 tools ship |
