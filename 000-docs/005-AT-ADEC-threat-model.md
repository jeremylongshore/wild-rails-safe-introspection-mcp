# Threat Model — wild-rails-safe-introspection-mcp

**Document type:** Architecture decision / security analysis
**Filed as:** `005-AT-ADEC-threat-model.md`
**Status:** Active
**Last updated:** 2026-03-17

---

## Purpose

This document identifies the anticipated attack surfaces for this server and describes how the architecture mitigates each one. It is the reference for adversarial testing (Epic 8) — every threat listed here should have a corresponding test that proves the mitigation works.

---

## Threat 1: Prompt Injection Through Tool Parameters

### Attack

An AI agent (or a malicious user directing an agent) provides a tool parameter value that is designed to be interpreted as code rather than data. Examples:

- Model name: `User; DROP TABLE users;`
- Filter value: `1 OR 1=1`
- Record ID: `__send__(:destroy_all)`

### Impact if unmitigated

Arbitrary SQL execution, data destruction, or Ruby method dispatch on attacker-controlled input.

### Mitigation

- Model names are resolved by exact string match against the allowlist hash — never by `constantize`, `const_get`, or any reflective resolution
- Filter values are passed as parameterized query bindings (`where(field => value)`) — never interpolated into SQL strings
- Record IDs are passed to `find_by(id: value)` — never used in string interpolation or method dispatch
- No `eval`, `instance_eval`, `send`, or `public_send` is used with any user-provided value

### Verification

Epic 8 must include tests that pass malicious strings as model names, filter values, and record IDs and confirm they are treated as inert data.

---

## Threat 2: Credential Abuse and Unauthorized Access

### Attack

An attacker obtains a valid API key or token and uses it to access data they should not have access to, or uses an expired/revoked credential that the system fails to reject.

### Impact if unmitigated

Unauthorized data access with a valid-looking identity in the audit trail.

### Mitigation

- Every request must carry a valid identity — anonymous requests are rejected before reaching the adapter
- Token validation happens on every request, not just at session establishment
- Revoked or expired tokens are rejected at the identity layer
- The audit trail records the identity used, making credential abuse traceable
- Rate limiting (future phase) can detect anomalous usage patterns

### Verification

Epic 8 must include tests that use expired tokens, revoked tokens, malformed tokens, and missing tokens — and confirm all are rejected with correct audit records.

---

## Threat 3: Data Exfiltration Through Allowed Channels

### Attack

A legitimate or compromised user uses the allowed tool surface to systematically extract large amounts of data by:
- Iterating through record IDs one at a time
- Using different filter predicates to enumerate records
- Combining schema introspection with targeted lookups to map the full database

### Impact if unmitigated

Bulk data extraction that is technically "allowed" by each individual request but represents an unauthorized aggregate access pattern.

### Mitigation

- Row caps limit the amount of data returned per request
- The audit trail captures every lookup — patterns of systematic enumeration are visible in the logs
- Rate limiting (future phase) can throttle high-frequency access
- The denylist ensures the most sensitive data is never accessible regardless of access pattern
- Schema introspection reveals column names but not record values — knowing the schema does not grant access to data

### Residual risk

A sufficiently patient attacker with valid credentials can extract data one record at a time within the row cap. The mitigation is auditability: the extraction is visible in the audit trail. Future phases may add anomaly detection on audit log patterns.

### Verification

Epic 8 should test that row caps are enforced and that audit records are produced for every call in a rapid sequence — confirming the extraction would be visible.

---

## Threat 4: Query Abuse (Resource Exhaustion)

### Attack

An attacker crafts queries designed to consume excessive database resources:
- Queries against large tables without indexes
- Queries with filter predicates that force full table scans
- Rapid-fire queries intended to overwhelm the read replica

### Impact if unmitigated

Database performance degradation affecting the host Rails application's production workload.

### Mitigation

- Query timeouts cancel long-running queries before they consume excessive resources
- Row caps prevent unbounded result sets
- Read-replica routing isolates introspection queries from the primary write database
- The single-predicate filter constraint limits query complexity — no joins, no multi-predicate combinations, no subqueries
- Rate limiting (future phase) can throttle high-frequency access

### Verification

Epic 8 must include tests that submit queries designed to be slow (if possible against test fixtures) and confirm they are cancelled within the timeout window.

---

## Threat 5: Model and Schema Enumeration

### Attack

An attacker tries to discover which models exist in the application by:
- Guessing model names and observing denial responses
- Using error message differences to distinguish "model does not exist" from "model exists but is blocked"

### Impact if unmitigated

Leakage of the application's internal data model, which could inform more targeted attacks.

### Mitigation

- Denial responses do not distinguish between "model does not exist" and "model is not on the allowlist" — both return the same `model_not_allowed` response
- The response wording ("not on the access allowlist") does not confirm or deny model existence
- Schema introspection is only available for models on the allowlist

### Verification

Epic 8 must test that requests for non-existent models, for blocked models, and for unlisted models all produce identical denial responses.

---

## Threat 6: Audit Trail Tampering or Bypass

### Attack

An attacker (or a bug) finds a code path that either:
- Skips audit logging entirely
- Modifies existing audit records
- Produces incomplete audit records

### Impact if unmitigated

Loss of accountability. The server can no longer prove what was or was not accessed.

### Mitigation

- The audit trail is append-only — no application code path modifies or deletes records
- Every call path through the server routes through the audit layer — there is no "fast path" that bypasses it
- The audit middleware wraps the entire tool invocation pipeline, including error handlers — errors are audited too
- Audit record completeness is verified by tests that check every field is populated

### Verification

Epic 8 must include tests that exercise every call path (success, denial, timeout, error, auth failure) and confirm each produces a complete audit record with all required fields.

---

## Threat 7: Configuration Tampering

### Attack

An attacker modifies the allowlist or denylist configuration files to expand access or remove blocking rules.

### Impact if unmitigated

Expanded access that bypasses the intended safety model.

### Mitigation

- Policy files are loaded at server startup — runtime modification is not possible through the MCP interface
- File system permissions should restrict policy file access to the server's deployment user
- Changes to policy files are visible in version control
- Startup validation logs the loaded policy summary to the audit trail — operators can verify what policies are active

### Residual risk

An attacker with file system access to the server host can modify the configuration. This is an infrastructure security concern, not an application concern. The application assumes the configuration files are trustworthy at startup.

---

## Summary: Threat-to-Mitigation Map

| Threat | Primary mitigation | Secondary mitigation | Test coverage |
|--------|-------------------|---------------------|---------------|
| Prompt injection | Parameterized queries, allowlist lookup | No eval/send/constantize | Epic 8 |
| Credential abuse | Per-request validation, anonymous rejection | Audit trail | Epic 8 |
| Data exfiltration | Row caps, denylist | Audit trail visibility | Epic 8 |
| Query abuse | Timeouts, row caps | Read-replica routing | Epic 8 |
| Schema enumeration | Uniform denial responses | Allowlist-only introspection | Epic 8 |
| Audit bypass | Mandatory middleware, append-only storage | Completeness tests | Epic 8 |
| Config tampering | Startup-only loading, file permissions | Startup audit logging | Epic 8 |
