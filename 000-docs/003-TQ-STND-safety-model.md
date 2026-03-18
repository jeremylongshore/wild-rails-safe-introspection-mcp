# Safety Model — wild-rails-safe-introspection-mcp

**Document type:** Safety standard
**Filed as:** `003-TQ-STND-safety-model.md`
**Status:** Active — governing spec for all implementation
**Last updated:** 2026-03-17

---

## Purpose

This document is the canonical safety specification for `wild-rails-safe-introspection-mcp`. Every implementation decision in this repo must be evaluated against the rules defined here. If the code contradicts this document, the code is wrong.

This is not aspirational guidance. These are enforceable constraints.

---

## 1. Read-Only Enforcement

### Rule

The system has no write paths. This is a design constraint, not a configuration option.

### What this means in practice

- No ActiveRecord methods that trigger writes: `save`, `save!`, `create`, `create!`, `update`, `update!`, `update_all`, `destroy`, `destroy!`, `destroy_all`, `delete`, `delete_all`, `insert`, `insert_all`, `upsert`, `upsert_all`, `touch`, `increment!`, `decrement!`, `toggle!`
- No raw SQL that contains `INSERT`, `UPDATE`, `DELETE`, `DROP`, `ALTER`, `TRUNCATE`, `CREATE`, `GRANT`, `REVOKE`
- No `ActiveRecord::Base.connection.execute` with write SQL
- No `eval`, `instance_eval`, `class_eval`, `send`, or `public_send` with user-supplied method names
- No callbacks that trigger writes as side effects (e.g., `after_find` hooks that update timestamps)

### Enforcement layers

1. **Database credentials** — connect with a read-only database user where infrastructure supports it
2. **Read-replica routing** — route all queries to a read replica when configured
3. **Application-level guard** — the Rails adapter explicitly refuses any operation that could write, even if the DB credentials would technically allow it
4. **Code review rule** — any PR that introduces a write-capable code path is a safety defect

### When no read-replica is available

If no read replica is configured, the system connects to the primary database with read-only credentials. If read-only credentials are not available, the system may connect to the primary with full credentials but the application-level guard is the enforcing layer. This fallback must be logged as an audit event so operators know the structural guarantee is downgraded.

---

## 2. Allowlist-Based Model Access

### Rule

Models are not accessible by default. Access is granted through an explicit allowlist. Any model not on the allowlist is refused.

### What this means in practice

- The allowlist is defined in a configuration file (YAML)
- Each entry specifies the model name and optionally which columns are accessible
- A query for a model not on the allowlist returns a denial response
- New models added to the Rails application do not automatically become accessible
- The allowlist is loaded at server startup and is not modifiable at runtime without a restart

### Allowlist entry format

```yaml
allowed_models:
  - name: Account
    columns: all_except_blocked    # uses denylist for column filtering
  - name: User
    columns: [id, email, name, created_at, updated_at, status]  # explicit column list
  - name: FeatureFlag
    columns: all                   # all columns accessible (no sensitive data)
```

### Denial response

When a model is not on the allowlist:
```json
{
  "status": "denied",
  "reason": "model_not_allowed",
  "message": "The model 'CreditCard' is not on the access allowlist.",
  "tool": "lookup_record_by_id",
  "timestamp": "2026-03-17T14:30:00Z"
}
```

The denial response must not reveal information about the model's existence or schema. "Not on the access allowlist" is sufficient — do not say "this model exists but is blocked."

---

## 3. Denylist for Sensitive Resources

### Rule

On top of the allowlist, a denylist blocks access to specific models, columns, and tables. The denylist takes precedence over the allowlist. A model can be on the allowlist but have specific columns blocked by the denylist.

### What this means in practice

- The denylist is defined in a configuration file (YAML), separate from the allowlist
- Denylist entries can block entire models or specific columns
- When a denylist blocks a column, that column is silently stripped from results — it does not appear in the output
- The denylist is always checked after the allowlist
- Precedence: denylist wins over allowlist, always

### Denylist entry format

```yaml
blocked_resources:
  models:
    - CreditCard
    - ApiKey
    - SessionToken
    - AuditLog    # internal audit logs are not exposed through introspection
  columns:
    - model: User
      columns: [password_digest, encrypted_password, otp_secret, recovery_codes]
    - model: Account
      columns: [stripe_customer_id, billing_token, tax_id]
    - model: "*"               # applies to all models
      columns: [ssn, social_security_number, credit_card_number]
```

### Column stripping behavior

Blocked columns are stripped silently from results. The response does not indicate which columns were removed. This prevents information leakage about what sensitive data exists.

---

## 4. Row Caps

### Rule

All queries that return records enforce a maximum row count. Queries that would return more rows than the cap are truncated, not failed.

### Defaults

| Parameter | Default | Configurable |
|-----------|---------|-------------|
| `max_rows` | 50 | Yes, via config |
| Hard ceiling | 1000 | Not configurable — safety max |

### Behavior

- If a query matches more rows than `max_rows`, only the first `max_rows` are returned
- The response includes a `truncated: true` flag and a `total_matching` count (if available without additional query cost)
- The truncation is logged in the audit trail
- Schema introspection (`inspect_model_schema`) is not subject to row caps — it returns metadata, not records

---

## 5. Query Timeouts

### Rule

All queries enforce a wall-clock timeout. Queries that exceed the timeout are cancelled.

### Defaults

| Parameter | Default | Configurable |
|-----------|---------|-------------|
| `query_timeout_ms` | 5000 | Yes, via config |
| Hard ceiling | 30000 | Not configurable — safety max |

### Behavior

- The timeout is enforced at the database level (`SET LOCAL statement_timeout`) where supported, and at the application level as a fallback
- A timed-out query returns an error response, not partial results
- The timeout is logged in the audit trail with the query duration at cancellation

---

## 6. Identity and Authorization

### Rule

Every invocation must carry a known caller identity. Anonymous invocations are rejected before reaching the adapter or guard.

### What this means in practice

- The MCP session must provide a caller identity (API key, token, or service account identifier)
- The identity is validated before any tool handler runs
- The validated identity is propagated through the entire call pipeline and recorded in the audit trail
- Anonymous requests receive a denial response and are logged as auth failures

### Identity in audit records

Every audit record contains:
- `caller_id` — the resolved identity string
- `caller_type` — the kind of identity (api_key, service_account, token)
- `auth_result` — success, rejected, or invalid

---

## 7. Audit Trail

### Rule

Every tool invocation produces a structured audit record regardless of outcome. Successes, denials, timeouts, and errors are all logged. Audit records are append-only.

### Audit record schema

```json
{
  "id": "uuid",
  "timestamp": "ISO 8601",
  "caller_id": "string",
  "caller_type": "api_key | service_account | token",
  "tool_name": "inspect_model_schema | lookup_record_by_id | find_records_by_filter",
  "model_name": "string | null",
  "parameters": {
    "sanitized": true,
    "fields": {}
  },
  "guard_result": "allowed | denied_model | denied_column | denied_timeout | denied_row_cap",
  "outcome": "success | denied | timeout | error",
  "duration_ms": 42,
  "rows_returned": 0,
  "truncated": false,
  "error_message": "string | null",
  "read_replica_used": true,
  "server_version": "0.1.0"
}
```

### Parameter sanitization

Before recording parameters in the audit trail:
- Record IDs are logged (they are the lookup key)
- Filter field names are logged
- Filter values are logged only if the column is not on the denylist
- Full record contents are never logged — only the count of rows returned

### Storage

Audit records are written to a structured log (JSON lines file by default). The storage backend is pluggable. Audit records are never modified or deleted through the application.

---

## 8. Tool Parameter Safety

### Rule

Tool parameters are treated as data, not code. No parameter value is ever evaluated, executed, or used for dynamic method dispatch.

### What this means in practice

- Model names are looked up by exact string match against the allowlist — not by calling `constantize` or `const_get` on user input
- Column names are validated against the model's known schema — not used as method names
- Filter values are passed as parameterized query values — never interpolated into SQL
- Record IDs are treated as opaque values passed to `find_by(id: value)` — not used in string interpolation

### Prohibited patterns

```ruby
# NEVER do this:
model_name.constantize                    # arbitrary class resolution
Object.const_get(model_name)             # same problem
model.send(user_provided_method)         # arbitrary method dispatch
connection.execute("SELECT * FROM #{table}")  # SQL injection
eval(user_input)                         # arbitrary code execution
```

### Required patterns

```ruby
# Always do this:
ALLOWED_MODELS[model_name]               # lookup in explicit allowlist hash
model_class.column_names.include?(col)   # validate against known schema
model_class.where(field => value).limit(max_rows)  # parameterized query
```

---

## 9. Conservative Defaults

### Rule

When a design decision involves choosing between more permissive and more restrictive behavior, choose restrictive. Operators can expand access through configuration. Contracting access after exposure is harder.

### Examples

- Default allowlist: empty (no models accessible until configured)
- Default row cap: 50 (low enough to be safe, high enough to be useful)
- Default timeout: 5 seconds (conservative for read queries)
- Default sharing scope: n/a (this repo does not expose sharing)
- Unknown model: denied (not "try to find it anyway")
- Unknown column: stripped (not "include it and hope")

---

## 10. Safety Defect Definition

A **safety defect** is any code that, if deployed, would allow:

1. A write operation to reach the database through any code path
2. A blocked model to be accessed through any tool
3. A blocked column to appear in any tool response
4. A query to exceed the hard ceiling row cap or timeout
5. An anonymous (no-identity) invocation to reach the adapter
6. A tool invocation to proceed without producing an audit record
7. A tool parameter to be evaluated as code
8. A model name to be resolved through `constantize`, `const_get`, or equivalent

If any of these conditions are discovered, the defect must be fixed before the affected code ships. There is no "we'll fix it later" path for safety defects.
