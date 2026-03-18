# Tool Catalog — wild-rails-safe-introspection-mcp

**Document type:** Reference
**Filed as:** `010-DR-REFF-tool-catalog.md`
**Status:** Active
**Last updated:** 2026-03-18

---

## 1. Server Overview

| Property | Value |
|----------|-------|
| Server name | `wild-rails-safe-introspection` |
| Version | `0.1.0` |
| Protocol | MCP (Model Context Protocol) via `mcp` gem |
| Tool count | 3 (fixed, not dynamically registered) |

All tools are read-only, idempotent, and non-destructive. These properties are declared via MCP tool annotations (`read_only_hint: true`, `destructive_hint: false`, `idempotent_hint: true`).

---

## 2. Trust Pipeline

Every tool invocation passes through the same pipeline before any data is returned:

1. **Identity resolution** — API key extracted from `server_context`, resolved to a `RequestContext` via `Identity::IdentityResolver`
2. **Capability gate check** — `Identity::CapabilityGate.permitted?` verifies the caller has access (v1 stub: all authenticated callers pass)
3. **Query guard** — `Guard::QueryGuard` enforces the access allowlist, denylist column stripping, row caps, and timeouts
4. **Audit recording** — `Audit::Recorder.record` wraps every invocation, capturing outcome, duration, caller, and parameters
5. **Response formatting** — `ToolHandler.format_response` wraps the result as `MCP::Tool::Response` with a single JSON text block

Gate denial short-circuits at step 2 (the query guard is never reached). Auth denial short-circuits at step 3 (the adapter is never reached).

Cross-references: [003 — Safety Model](003-TQ-STND-safety-model.md), [008 — Identity & Auth](008-AT-ADEC-identity-and-auth-model.md), [009 — Capability Gate](009-AT-ADEC-capability-gate-interface.md)

---

## 3. Tool Reference

### 3.1 `inspect_model_schema`

**Purpose:** Inspect the column types and associations of a Rails model.

**Input:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `model_name` | string | yes | Rails model class name (e.g. `"Account"`, `"User"`) |

**Safety classification:** `schema_inspection`

**Success response:**

```json
{
  "status": "ok",
  "model": "Account",
  "table_name": "accounts",
  "columns": [
    { "name": "id", "type": "integer", "sql_type": "integer", "nullable": false, "default": null }
  ],
  "associations": [
    { "name": "users", "type": "has_many", "target_model": "User", "foreign_key": "account_id" }
  ]
}
```

Columns in the response are filtered by the access policy — blocked columns are silently stripped before the response leaves the system.

**Denial responses:**

| Condition | Response |
|-----------|----------|
| Model not on allowlist | `{ "status": "denied", "reason": "model_not_allowed" }` |
| Not authenticated | `{ "status": "denied", "reason": "auth_required" }` |
| Capability gate failure | `{ "status": "denied", "reason": "insufficient_capability" }` |

---

### 3.2 `lookup_record_by_id`

**Purpose:** Fetch a single record by its primary key.

**Input:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `model_name` | string | yes | Rails model class name (e.g. `"Account"`, `"User"`) |
| `id` | string | yes | The record primary key value |

**Safety classification:** `record_lookup`

**Success response:**

```json
{
  "status": "ok",
  "record": { "id": 1, "name": "Acme Corp", "created_at": "2026-01-01T00:00:00Z" }
}
```

The record has blocked columns silently stripped before the response is returned.

**Other responses:**

| Condition | Response |
|-----------|----------|
| Record not found | `{ "status": "not_found", "message": "No record found." }` |
| Query timeout | `{ "status": "error", "reason": "query_timeout" }` |
| Model not on allowlist | `{ "status": "denied", "reason": "model_not_allowed" }` |
| Not authenticated | `{ "status": "denied", "reason": "auth_required" }` |
| Capability gate failure | `{ "status": "denied", "reason": "insufficient_capability" }` |

Note: `not_found` is a valid outcome, not an error — the MCP response has `error: false`.

---

### 3.3 `find_records_by_filter`

**Purpose:** Find records matching a single field/value filter.

**Input:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `model_name` | string | yes | Rails model class name (e.g. `"Account"`, `"User"`) |
| `field` | string | yes | Column name to filter on (must be in access allowlist) |
| `value` | string | yes | Value to match against the filter field |

**Safety classification:** `filtered_lookup`

**Success response:**

```json
{
  "status": "ok",
  "records": [
    { "id": 1, "name": "Acme Corp" },
    { "id": 2, "name": "Acme LLC" }
  ],
  "truncated": false,
  "count": 2
}
```

The filter field must be in the access allowlist — filtering on a blocked column results in denial. Records have blocked columns silently stripped. Results are capped at the configured `max_rows` (default 50, hard ceiling 1000). When results exceed the cap, `truncated` is `true` and only `max_rows` records are returned.

**Other responses:**

| Condition | Response |
|-----------|----------|
| Filter field not in allowlist | `{ "status": "denied", "reason": "model_not_allowed" }` |
| Query timeout | `{ "status": "error", "reason": "query_timeout" }` |
| Model not on allowlist | `{ "status": "denied", "reason": "model_not_allowed" }` |
| Not authenticated | `{ "status": "denied", "reason": "auth_required" }` |
| Capability gate failure | `{ "status": "denied", "reason": "insufficient_capability" }` |

---

## 4. Response Format

All tool responses are wrapped in MCP's standard response structure:

```ruby
MCP::Tool::Response.new([{ type: 'text', text: JSON.generate(result) }], error: error)
```

- Content is always a single JSON text block inside a one-element array
- `error: false` for `:ok` and `:not_found` outcomes (valid results)
- `error: true` for `:denied` and `:error` outcomes (caller should not retry without changes)

The `error` flag is determined by `ToolHandler.format_response`:

```ruby
error = %i[denied error].include?(result[:status])
```

---

## 5. Safety Classifications

| Tool | Classification | Read-only | Allowlist | Denylist strip | Filter field check | Row cap | Timeout | Audit |
|------|---------------|-----------|-----------|---------------|-------------------|---------|---------|-------|
| `inspect_model_schema` | `schema_inspection` | yes | yes | yes | n/a | n/a | n/a | yes |
| `lookup_record_by_id` | `record_lookup` | yes | yes | yes | n/a | n/a (single) | yes | yes |
| `find_records_by_filter` | `filtered_lookup` | yes | yes | yes | yes | yes (default 50, max 1000) | yes | yes |

All three tools share: read-only enforcement, model allowlist gating, denylist column stripping, and full audit recording.

---

## 6. What Is Not Supported

Current boundaries of the v1 tool surface:

- **No write operations** of any kind — no create, update, delete, or raw SQL mutation
- **No arbitrary SQL or Ruby execution** — tool parameters are data, never code
- **No cross-model joins or complex queries** — each tool operates on a single model
- **No transport layer** — the MCP server exists but has no HTTP/stdio transport yet (Epic 9)
- **No real capability gating** — v1 stub permits all authenticated callers; fine-grained gating ships with `wild-capability-gate` (Epic 10)
- **No streaming or pagination** — results beyond the row cap are truncated, not paginated
- **No dynamic tool registration** — the tool set is fixed at 3 tools, defined in `ServerFactory::TOOLS`

---

## 7. Audit Record Fields

Every invocation produces an `Audit::AuditRecord` with these fields:

| Field | Description |
|-------|-------------|
| `id` | UUID (auto-generated) |
| `timestamp` | UTC ISO 8601 with milliseconds |
| `caller_id` | Resolved caller identity (or `"anonymous"`) |
| `caller_type` | Caller type classification (or `"unknown"`) |
| `tool_name` | Which tool was invoked |
| `model_name` | Target model name |
| `parameters` | Tool input parameters |
| `guard_result` | The raw result hash from the guard/adapter |
| `outcome` | Derived outcome category |
| `duration_ms` | Wall-clock duration of the invocation |
| `rows_returned` | Number of rows in the response |
| `truncated` | Whether results were truncated by row cap |
| `error_message` | Error detail (if applicable) |
| `read_replica_used` | Whether a read replica was used |
| `server_version` | Server version at time of invocation |
