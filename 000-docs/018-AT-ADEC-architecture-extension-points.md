# Architecture Extension Points — wild-rails-safe-introspection-mcp

**Document type:** Architecture decision record
**Filed as:** `018-AT-ADEC-architecture-extension-points.md`
**Status:** Active — documents existing extension points in shipped v1 code
**Last updated:** 2026-03-18
**Epic:** 10 — Expansion Readiness
**Task:** 1cv.3 — Document the architecture extension points

---

## Purpose

This document maps the points in the v1 architecture where new tools, policy types, identity providers, and audit backends can be added without breaking the existing safety model. Each extension point describes what it is, where it lives in code, what the contract is, and what safety constraints must hold when extending it.

This is a map of the architecture as built, not speculation about what might be built.

---

## 1. Adding New Tools

### Where

- Tool class: `lib/wild_rails_safe_introspection/server/tools/<tool_name>.rb`
- Registration: `lib/wild_rails_safe_introspection/server/server_factory.rb` — add to `TOOLS` array
- Require: `lib/wild_rails_safe_introspection.rb` — add `require_relative` line

### Pattern

Every tool follows the same structure. Here is the template derived from the three v1 tools:

```ruby
class NewTool < MCP::Tool
  tool_name 'new_tool_name'
  description 'What this tool does.'

  input_schema(
    properties: { ... },
    required: [...]
  )

  annotations(
    read_only_hint: true,
    destructive_hint: false,
    idempotent_hint: true
  )

  class << self
    def call(**params, server_context: nil)
      ToolHandler.execute(
        action: 'new_tool_name',
        resource: params[:model_name],
        server_context: server_context
      ) do |request_context|
        Guard::QueryGuard.new_method(params, request_context: request_context)
      end
    end
  end
end
```

### Contract

1. **Must subclass `MCP::Tool`** — not a module, not a plain method
2. **Must delegate through `ToolHandler.execute`** — this enforces the identity → gate → guard → audit pipeline. Direct adapter calls bypass safety.
3. **Must add a corresponding `QueryGuard` method** — the guard enforces allowlist, denylist, caps, timeouts, and wraps the call in `Audit::Recorder.record`
4. **Must register in `ServerFactory::TOOLS`** — the array is frozen at boot. No runtime modification.
5. **Must set MCP annotations** — `read_only_hint: true`, `destructive_hint: false`, `idempotent_hint: true` are non-negotiable for this repo
6. **Must add action to `CapabilityGate::ACTIONS`** — and to `capabilities.yml` when the real gate is integrated

### Safety constraints

- No new tool may introduce a write path
- No tool parameters may be evaluated as code
- The tool's `QueryGuard` method must wrap everything in `Audit::Recorder.record`
- Denial responses must use the existing format (`{ status: :denied, reason: :symbol, ... }`)
- New adversarial tests must cover the tool's specific attack surface

### What does NOT need to change

- `ToolHandler.execute` — generic, not tool-specific
- `format_response` — works for any result hash
- `Audit::Recorder` — tool-agnostic, records whatever the guard yields
- `IdentityResolver` — identity is tool-independent
- MCP server creation — `ServerFactory.create` reads the `TOOLS` array, no per-tool wiring

---

## 2. Extending the Query Guard

### Where

- `lib/wild_rails_safe_introspection/guard/query_guard.rb`
- `lib/wild_rails_safe_introspection/guard/column_resolver.rb`
- `lib/wild_rails_safe_introspection/guard/result_filter.rb`

### Current shape

`QueryGuard` has three public methods, one per v1 tool:

| Method | Tool |
|--------|------|
| `inspect_schema` | `inspect_model_schema` |
| `find_by_id` | `lookup_record_by_id` |
| `find_by_filter` | `find_records_by_filter` |

Each method follows the same internal pattern:

1. Build recorder options (tool name, model name, parameters, request context)
2. Wrap in `Audit::Recorder.record`
3. Check authentication
4. Resolve accessible columns via `ColumnResolver`
5. Delegate to an adapter module
6. Filter results via `ResultFilter`
7. Return the result hash

### How to extend

Add a new public method to `QueryGuard` for each new tool. The method must follow the same pattern above. The guard is the enforcement boundary — it sits between the tool handler and the adapter.

### Reusable components

- **`ColumnResolver.accessible_columns(model_name)`** — returns the set of allowed columns for a model, accounting for both allowlist and denylist. Usable by any tool that operates on model data.
- **`ResultFilter.filter_record(record, accessible)`** — strips blocked columns from a single record hash. Usable by any tool returning record data.
- **`ResultFilter.filter_records(records, accessible)`** — same, for arrays.
- **`ResultFilter.filter_schema_columns(columns, accessible)`** — same, for schema column metadata.

### Safety constraints

- New guard methods must always wrap in `Audit::Recorder.record` — no un-audited code paths
- New guard methods must check `request_context.authenticated?` before any data access
- New guard methods must call `ColumnResolver.accessible_columns` before returning data
- New guard methods must call `ResultFilter` before returning data

---

## 3. Extending the Access Policy

### Where

- Policy files: `config/access_policy.yml` and `config/blocked_resources.yml`
- Loader: `lib/wild_rails_safe_introspection/configuration.rb`

### Current policy types

**Access policy (`access_policy.yml`):**
- `allowed_models` — array of model entries with name, columns mode, per-model row caps, per-model timeouts
- `defaults` — global `max_rows` and `query_timeout_ms`

**Blocked resources (`blocked_resources.yml`):**
- `blocked_models` — array of model name strings
- `blocked_columns` — array of `{ model, columns }` entries (supports `"*"` wildcard)

### How to extend

**Adding a new model to the allowlist:** Add an entry to `allowed_models` in `access_policy.yml` and restart the server. No code changes required.

**Adding new policy types:** The `Configuration` class loads both YAML files in `load!` and builds the `model_registry`. To add a new policy concept (e.g., per-model rate limits, per-caller model restrictions):

1. Add the new field to the YAML schema (with a version bump)
2. Parse it in the corresponding `load_*!` method
3. Store it on the `Configuration` instance (with a reader)
4. Freeze it in `freeze_policy_data!`
5. Consume it in the appropriate guard method

### Safety constraints

- Policy changes require server restart — no runtime modification
- The denylist always takes precedence over the allowlist (enforced in `build_model_registry!`)
- Hard ceilings on row caps (1000) and timeouts (30s) are not configurable — they are constants in `Configuration`
- New policy types must not weaken existing safety invariants

### What would NOT be safe

- Runtime-modifiable policy (breaks the startup-only loading guarantee from Decision 7 in Doc 006)
- Policy that grants access to non-allowlisted models (breaks the allowlist invariant)
- Policy that overrides hard ceilings (breaks resource limit guarantees)

---

## 4. Replacing the Identity Provider

### Where

- `lib/wild_rails_safe_introspection/identity/identity_resolver.rb`
- `lib/wild_rails_safe_introspection/identity/request_context.rb`

### Current implementation

`IdentityResolver.resolve(api_key:)` performs a constant-time comparison against a configured list of API keys and returns a `RequestContext` with `caller_id`, `caller_type`, and `auth_result`.

### Extension point: the `RequestContext` contract

Any identity provider replacement must produce a `RequestContext` with:

| Method | Type | Purpose |
|--------|------|---------|
| `authenticated?` | Boolean | Whether the caller identity was validated |
| `caller_id` | String | Opaque caller identity string |
| `caller_type` | String | Identity type classification |

The rest of the system depends only on `RequestContext` — not on how the identity was resolved. This makes the identity provider swappable.

### How to replace

To support a different identity mechanism (e.g., JWT tokens, OAuth2, mTLS client certificates):

1. Create a new resolver module (e.g., `Identity::JwtResolver`)
2. Implement `resolve(token:)` that returns a `RequestContext`
3. Replace the call in `ToolHandler.resolve_identity` to route to the new resolver based on the credential type present in `server_context`
4. Or: modify `IdentityResolver.resolve` to detect the credential format and delegate

### Safety constraints

- **Constant-time comparison** must be used for any secret comparison (API keys, tokens). The v1 implementation uses `ActiveSupport::SecurityUtils.secure_compare`.
- **Anonymous rejection** must be preserved — a missing or empty credential returns `RequestContext.anonymous`, which fails `authenticated?`
- **Invalid credentials** must return a `RequestContext` with `auth_result: :invalid`, not raise an exception
- **The `RequestContext` contract is stable** — changing it would require updating every consumer (ToolHandler, QueryGuard, Audit::Recorder, CapabilityGate)

---

## 5. Replacing the Audit Backend

### Where

- `lib/wild_rails_safe_introspection/audit/audit_logger.rb`
- `lib/wild_rails_safe_introspection/audit/audit_record.rb`
- `lib/wild_rails_safe_introspection/audit/recorder.rb`
- `lib/wild_rails_safe_introspection/audit/parameter_sanitizer.rb`

### Current implementation

`AuditLogger.log(audit_record)` appends a JSON line to a file at the configured `audit_log_path`. The path is set via `Configuration`.

### Extension point: `AuditLogger.log`

`AuditLogger.log` is the single output point for all audit records. The `Recorder` builds the `AuditRecord` and calls `AuditLogger.log`. To change where audit records go, only `AuditLogger` needs to change.

### How to replace

To send audit records to a different backend (database table, log aggregation service, message queue):

1. Modify `AuditLogger.log` to write to the new backend
2. Or: add a pluggable backend system where `AuditLogger` delegates to a configured backend class
3. The `AuditRecord` structure (`.to_h`) is the serialization format — backends receive a flat hash

### What stays the same

- `Recorder` — wraps every tool invocation, captures timing, maps outcomes. Backend-agnostic.
- `AuditRecord` — data structure for audit fields. Backend-agnostic.
- `ParameterSanitizer` — strips sensitive values from parameters before recording. Backend-agnostic.

### Safety constraints

- **Every invocation must produce an audit record** — the backend may change but the guarantee must not. `Recorder.record` is called in `ensure` blocks so it runs even when exceptions occur.
- **Append-only semantics** — the backend must not allow modification or deletion of audit records through the application
- **No audit record suppression** — even if the backend is unavailable, the record should at minimum be logged to stderr as a fallback (not currently implemented — a hardening opportunity)

---

## 6. Replacing the Capability Gate

### Where

- `lib/wild_rails_safe_introspection/identity/capability_gate.rb`

### Current implementation

v1 stub: `permitted?` returns `request_context.authenticated?`. All authenticated callers pass. Doc 016 describes the full integration plan for the real `wild-capability-gate` gem.

### Extension point: `CapabilityGate.permitted?`

```ruby
CapabilityGate.permitted?(request_context, action:, resource:) → Boolean
```

This is called by `ToolHandler.check_gate` before yielding to the guard. The interface is stable — the implementation is replaceable.

### How to replace

See [Doc 016 — Capability Gate Integration Plan](016-AT-ADEC-capability-gate-integration-plan.md) for the complete step-by-step plan. The key points:

- Replace stub logic with delegation to `Wild::CapabilityGate#evaluate`
- Map `request_context.caller_id` → gate caller string
- Map `action` → gate capability
- Map `resource` → gate context hash
- Translate `EvaluationResult.allowed?` → boolean return

### Safety constraints

- **Fail-closed** — if the gate errors, the result must be denial, not permission
- **`authenticated?` pre-check preserved** — the identity layer rejects anonymous callers before the gate is consulted
- **`denial_response` format unchanged** — downstream consumers (ToolHandler, audit) depend on the hash shape
- **Signature unchanged** — `(request_context, action:, resource:)` must not change

---

## 7. Adding New Adapter Operations

### Where

- `lib/wild_rails_safe_introspection/adapter/` — one module per operation type

### Current modules

| Module | Purpose |
|--------|---------|
| `SchemaInspector` | Model schema introspection (columns, associations) |
| `RecordLookup` | Single record by ID |
| `FilteredLookup` | Records by single-predicate filter |
| `ModelResolver` | Model name → class + metadata resolution |
| `ModelReflector` | Association reflection |
| `ConnectionManager` | Read-replica routing |
| `WritePrevention` | Static analysis to verify no write methods exist |

### How to add

New adapter modules follow the pattern:

1. Create a module in `adapter/`
2. Accept model name, parameters, and use `ModelResolver` to get the class
3. Use `ConnectionManager.connection` for database access (ensures read-replica routing)
4. Return a result hash with `:status` and tool-specific fields
5. Add `require_relative` in `lib/wild_rails_safe_introspection.rb`

### Safety constraints

- **All data access through `ConnectionManager.connection`** — no direct `ActiveRecord::Base.connection` calls (ensures replica routing)
- **Model resolution through `ModelResolver` or `Configuration.resolve_model`** — no `constantize`, no `const_get`
- **Parameterized queries only** — `where(field => value)`, never string interpolation
- **Row caps applied with `.limit(max_rows)`** — no unbounded queries
- **Timeout enforcement** — use the configured `query_timeout_ms` (adapter modules receive this via model config)
- **No write methods** — `WritePrevention` verifies this statically in the test suite

---

## 8. Extension Point Summary

| Extension point | Location | Contract boundary | Safe to extend without code review? |
|----------------|----------|-------------------|--------------------------------------|
| New MCP tool | `server/tools/`, `ServerFactory::TOOLS` | `MCP::Tool` subclass, delegates through `ToolHandler` | No — requires PR with safety review |
| New guard method | `guard/query_guard.rb` | Follows audit-wrap + auth-check + column-resolve + filter pattern | No — requires PR with safety review |
| New allowlisted model | `config/access_policy.yml` | YAML entry + server restart | Yes — operator config change |
| New blocked resource | `config/blocked_resources.yml` | YAML entry + server restart | Yes — operator config change |
| New policy type | `Configuration` class | Parse in `load!`, freeze in `freeze_policy_data!` | No — requires PR |
| Identity provider | `identity/identity_resolver.rb` | Must return `RequestContext` | No — requires PR with security review |
| Audit backend | `audit/audit_logger.rb` | Receives `AuditRecord#to_h` | No — requires PR |
| Capability gate | `identity/capability_gate.rb` | `permitted?(request_context, action:, resource:)` → Boolean | No — requires PR (see Doc 016) |
| New adapter operation | `adapter/` module | Uses `ModelResolver`, `ConnectionManager`, returns result hash | No — requires PR with safety review |

### The safety boundary

Config-only changes (adding models to allowlist, blocking resources) are safe for operators to make without code review. Everything else — new tools, new guard methods, new identity providers, new audit backends — crosses the safety boundary and requires a PR with review and adversarial testing.

This is by design. The architecture makes config changes safe and code changes visible.

---

## Reference Documents

| Document | Relevance |
|----------|-----------|
| [006 — Safety Architecture Decisions](006-AT-ADEC-safety-architecture-decisions.md) | Decisions that created these extension points |
| [010 — Tool Catalog](010-DR-REFF-tool-catalog.md) | v1 tool definitions — the pattern new tools follow |
| [016 — Capability Gate Integration Plan](016-AT-ADEC-capability-gate-integration-plan.md) | Detailed plan for gate extension point |
| [017 — v2 Tool Additions](017-PP-PLAN-v2-tool-additions.md) | Planned tools that would use these extension points |
| [003 — Safety Model](003-TQ-STND-safety-model.md) | Constraints that all extensions must satisfy |
