# Identity and Authorization Model — wild-rails-safe-introspection-mcp

**Document type:** Architecture decision record
**Filed as:** `008-AT-ADEC-identity-and-auth-model.md`
**Status:** Active — implemented in Epic 6
**Last updated:** 2026-03-18

---

## Purpose

This document records how caller identity is represented, validated, and propagated through the system. It is the governing reference for how the server knows who is calling and what to record in the audit trail.

---

## Decision 1: API Key as the v1 Identity Mechanism

**Context:** The server needs to identify callers. Options range from simple API keys to OAuth flows to mutual TLS.

**Decision:** v1 uses API keys configured in the server's startup configuration. Each key maps to a caller name.

**Rationale:** API keys are the simplest mechanism that satisfies the safety model's requirement that every invocation carry a known identity. They are easy to configure, easy to rotate, and easy to audit. More sophisticated auth mechanisms (OAuth, service accounts with token exchange) can be added in later phases without changing the identity abstraction.

**Configuration format:**
```ruby
config.api_keys = [
  { key: 'sk-production-key-1', name: 'agent-alpha' },
  { key: 'sk-production-key-2', name: 'agent-beta' }
]
```

**Trade-off:** API keys have no expiration, no scoping, and no built-in rotation mechanism. Operators must manage key lifecycle manually. This is acceptable for v1 because the server is deployed in controlled environments where key management is an operational concern, not a product concern.

---

## Decision 2: RequestContext as the Identity Carrier

**Context:** The resolved identity needs to flow through the call pipeline — from auth check through guard through audit.

**Decision:** `Identity::RequestContext` is a frozen value object that carries `caller_id`, `caller_type`, and `auth_result` through the entire pipeline. It is created once per invocation and passed as a required keyword argument.

**Fields:**
- `caller_id` — the resolved identity string (e.g., `"agent-alpha"`) or `"anonymous"` / `"unknown"`
- `caller_type` — the kind of identity: `"api_key"` in v1, extensible to `"service_account"` / `"token"` later
- `auth_result` — `:success`, `:rejected` (no credentials), or `:invalid` (bad credentials)

**Rationale:** A frozen value object ensures the identity cannot be modified after resolution. Passing it as a required parameter (not thread-local or global state) makes the flow explicit and testable.

---

## Decision 3: Anonymous Rejection Before Guard Logic

**Context:** The safety model requires anonymous invocations to be rejected before reaching the adapter or guard.

**Decision:** `QueryGuard` checks `request_context.authenticated?` at the top of every public method, before any model resolution or policy check. Anonymous calls receive a uniform `auth_required` denial.

**Auth denial response:**
```ruby
{ status: :denied, reason: :auth_required, message: 'Authentication is required.' }
```

**Rationale:** Checking auth before guard logic means:
- No data access occurs for unauthenticated callers
- The auth denial does not reveal model existence (same response regardless of model name)
- The audit record captures the anonymous identity, making auth failures visible to operators

---

## Decision 4: Constant-Time Key Comparison

**Context:** API key validation must not leak information through timing differences.

**Decision:** `IdentityResolver` uses `ActiveSupport::SecurityUtils.secure_compare` for all key comparisons.

**Rationale:** Naive string comparison returns faster for keys that differ in the first byte, creating a timing side-channel. Constant-time comparison ensures an attacker cannot determine key validity through response timing.

---

## Identity Flow

```
Inbound request (with API key)
  → IdentityResolver.resolve(api_key:)
    → RequestContext (caller_id, caller_type, auth_result)
      → QueryGuard.method(model_name, ..., request_context:)
        → auth check (reject if not authenticated)
        → guard logic (policy enforcement)
        → Recorder.record(..., request_context:)
          → AuditRecord (caller_id, caller_type from context)
            → AuditLogger (JSONL with real identity)
```
