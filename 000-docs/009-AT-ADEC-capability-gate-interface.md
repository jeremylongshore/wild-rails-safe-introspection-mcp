# Capability Gate Interface — wild-rails-safe-introspection-mcp

**Document type:** Architecture decision record
**Filed as:** `009-AT-ADEC-capability-gate-interface.md`
**Status:** Active — stub implemented in Epic 6, integration planned for Epic 10
**Last updated:** 2026-03-18

---

## Purpose

This document defines the capability gate interface — the contract that tool handlers use to check whether a caller has the capability to perform a specific action. The interface is stubbed in v1 so that when `wild-capability-gate` ships, integration is a drop-in replacement, not a redesign.

---

## The Interface Contract

```ruby
Identity::CapabilityGate.permitted?(request_context, action:, resource:) → Boolean
Identity::CapabilityGate.denial_response → Hash
```

### `permitted?`

**Parameters:**
- `request_context` — an `Identity::RequestContext` carrying the resolved caller identity
- `action:` — a string identifying the tool action (e.g., `"inspect_model_schema"`)
- `resource:` — a string identifying the target resource (e.g., model name), or nil

**Returns:** `true` if the caller is permitted, `false` if denied.

**v1 stub behavior:** Returns `request_context.authenticated?` — all authenticated callers have full capability to all actions on all resources.

### `denial_response`

Returns a frozen hash suitable for returning directly from a tool handler:

```ruby
{ status: :denied, reason: :insufficient_capability, message: 'The caller does not have the required capability.' }
```

### Defined Actions

The v1 action vocabulary matches the tool surface:

| Action | Tool |
|--------|------|
| `inspect_model_schema` | Schema introspection |
| `lookup_record_by_id` | Single record lookup |
| `find_records_by_filter` | Filtered record search |

---

## v1 Stub Rationale

The stub exists so that:
1. The interface is defined and tested before Epic 7 (MCP server) builds tool handlers
2. Tool handlers can include the gate check call from day one
3. When `wild-capability-gate` ships, replacing the stub is a single-module change
4. No tool handler code needs to change — only `CapabilityGate.permitted?` internals

---

## Integration Plan for `wild-capability-gate`

When `wild-capability-gate` ships a stable public interface, the integration steps are:

1. Add `wild-capability-gate` as a dependency
2. Replace the stub logic in `CapabilityGate.permitted?` with:
   ```ruby
   WildCapabilityGate.check(
     caller_id: request_context.caller_id,
     action: action,
     resource: resource
   )
   ```
3. Add configuration for the gate connection (endpoint, credentials)
4. Add tests that verify gate-denied calls produce correct audit records
5. Update this document to reflect the live integration

**Critical constraint:** The `permitted?` method signature must not change. All existing call sites depend on `(request_context, action:, resource:)`.

---

## Where the Gate Gets Called

The gate is designed to be called by **tool handlers** (Epic 7), not by `QueryGuard` directly. The flow:

```
MCP tool handler receives request
  → resolve identity (IdentityResolver)
  → check capability (CapabilityGate.permitted?)
  → if denied: return denial_response, audit the denial
  → if permitted: call QueryGuard (which checks auth + policy)
```

This separation means:
- `QueryGuard` remains focused on data access policy (allowlist, denylist, caps)
- `CapabilityGate` handles action-level authorization
- Each layer has a single responsibility

---

## Cross-Epic Dependency Note

This interface is the contract between Epic 6 (identity) and Epic 10 (expansion readiness). If this interface is changed, Epic 10's capability gate integration plan must be updated to match. This relationship must be reviewed when Epic 10 is executed.
