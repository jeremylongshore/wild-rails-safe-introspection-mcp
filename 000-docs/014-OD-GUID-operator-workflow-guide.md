# 014 — Operator Workflow Guide

**Category:** OD — Operations & Deployment
**Type:** GUID — Guide
**Status:** v1

Step-by-step workflows for common operator tasks. Each workflow assumes a working deployment per the [Operator Deployment Guide (012)](012-OD-OPNS-operator-deployment-guide.md).

---

## Workflow 1: Add a New Allowed Model

**Goal:** Make a Rails model accessible to MCP callers.

### Pre-Addition Checklist

Before allowing a model, verify:

- [ ] The model is **not** on the `blocked_models` list in `blocked_resources.yml`. If it is, remove it first — blocked models override the allowlist.
- [ ] The model **does not contain PII** that should not be exposed (e.g., SSN, date of birth, government IDs). If it does, use explicit column lists or add entries to `blocked_columns`.
- [ ] The model **does not contain credentials** (passwords, tokens, secrets). If it does, add those columns to `blocked_columns` before allowing the model.
- [ ] The model class **will be loaded** when the initializer runs. If using autoloading, ensure the constant is available at boot time.

### Steps

**1. Edit `access_policy.yml`**

Add an entry under `allowed_models`:

```yaml
allowed_models:
  # ... existing models ...

  - name: Invoice
    columns: all_except_blocked
    max_rows: 100
    query_timeout_ms: 5000
```

**2. Choose a column exposure mode**

| Mode | When to Use |
|------|-------------|
| `all_except_blocked` | Default. Exposes all columns except those in `blocked_columns`. Use when the model is generally safe but has a few sensitive fields blocked elsewhere. |
| `["id", "amount", "status", "created_at"]` | Explicit list. Use when the model contains many columns and you want to expose only specific ones. |
| `all` | Exposes all columns, bypassing model-specific blocks. Use only for models with no sensitive data at all. Wildcard blocks still apply. |

**3. (Optional) Add blocked columns**

If the model has sensitive columns, add entries to `blocked_resources.yml`:

```yaml
blocked_columns:
  # ... existing entries ...

  - model: Invoice
    columns:
      - internal_notes
      - payment_token
```

**4. Restart the server**

Configuration is frozen at load time. Changes require a restart:

```bash
# Rails app
bin/rails restart

# Standalone
# Kill and restart the server process
```

**5. Test with `inspect_model_schema`**

Call the `inspect_model_schema` tool with the new model name. Verify:

- The model appears in the response
- The column list matches your expectations
- Blocked columns are **not present** in the response

**6. Verify blocked columns are stripped**

If you added blocked columns in step 3, confirm they do not appear in:

- Schema inspection results
- Record lookup results
- Filter query results

**7. Check the audit log**

Verify your test calls appear in the audit log:

```bash
tail -5 log/wild_introspection_audit.jsonl | jq .
```

Confirm entries show `"outcome": "success"` and the correct `model_name`.

---

## Workflow 2: Block a Column

**Goal:** Prevent a column from appearing in any MCP response.

### Steps

**1. Edit `blocked_resources.yml`**

Add a column block entry. Choose model-specific or wildcard:

```yaml
# Block on a specific model
blocked_columns:
  - model: User
    columns:
      - social_security_number

# Block on ALL models (wildcard)
blocked_columns:
  - model: "*"
    columns:
      - social_security_number
```

**2. Restart the server**

```bash
bin/rails restart
```

**3. Verify the column is stripped**

Test each tool that could return data from the affected model:

- **`inspect_model_schema`** — The blocked column must not appear in the `columns` array.
- **`lookup_record_by_id`** — The blocked column must not appear in record attributes.
- **`find_records_by_filter`** — The blocked column must not appear in any returned record. Additionally, filtering *by* a blocked column must be denied.

**4. Confirm in audit logs**

```bash
grep '"model_name":"User"' log/wild_introspection_audit.jsonl | tail -3 | jq .
```

Verify the calls completed successfully and the blocked column does not appear in any response data.

**Note:** Column blocking is silent. Callers receive no indication that columns were removed. This is by design — it prevents information leakage about what data exists.

---

## Workflow 3: Revoke Caller Access

**Goal:** Remove an API key so a specific caller can no longer authenticate.

### Steps

**1. Remove the API key from the initializer**

Edit the initializer and remove the key entry:

```ruby
# Before
config.api_keys = [
  { name: 'claude-agent', key: ENV.fetch('WILD_INTROSPECTION_API_KEY') },
  { name: 'monitoring-bot', key: ENV.fetch('MONITORING_API_KEY') }
]

# After — monitoring-bot revoked
config.api_keys = [
  { name: 'claude-agent', key: ENV.fetch('WILD_INTROSPECTION_API_KEY') }
]
```

**2. Restart the server**

```bash
bin/rails restart
```

**3. Verify calls are rejected**

Attempt a call using the revoked key. The response should be:

```json
{
  "status": "denied",
  "reason": "insufficient_capability",
  "message": "The caller does not have the required capability."
}
```

If the key is completely absent (nil), the response is:

```json
{
  "status": "denied",
  "reason": "auth_required",
  "message": "Authentication is required."
}
```

**4. Check audit log for denied entries**

```bash
grep '"outcome":"denied"' log/wild_introspection_audit.jsonl | tail -5 | jq .
```

Verify the revoked caller's attempts are logged with the appropriate denial reason.

---

## Workflow 4: Inspect Audit Logs

**Goal:** Understand what happened — who called what, when, and what was the outcome.

### Locate the Log File

The audit log path is set in the initializer via `config.audit_log_path`. A typical location:

```
log/wild_introspection_audit.jsonl
```

### Log Format

The file is JSONL — one JSON object per line. Each line is a complete audit record.

### Key Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique record identifier |
| `timestamp` | ISO 8601 | When the invocation occurred (UTC) |
| `caller_id` | String | Name of the authenticated caller (from `api_keys[].name`), or `"anonymous"` |
| `caller_type` | String | How the caller authenticated (e.g., `"api_key"`) |
| `tool_name` | String | Which tool was invoked: `inspect_model_schema`, `lookup_record_by_id`, or `find_records_by_filter` |
| `model_name` | String | Target model name |
| `parameters` | Object | Sanitized invocation parameters (sensitive filter values redacted) |
| `guard_result` | String | Policy decision: `allowed`, `denied_auth_required`, `denied_model_not_allowed`, etc. |
| `outcome` | String | High-level result: `success`, `denied`, `timeout`, or `error` |
| `duration_ms` | Integer | Wall-clock time in milliseconds |
| `rows_returned` | Integer | Number of records returned (0 for schema calls and denials) |
| `truncated` | Boolean | `true` if the result was truncated by `max_rows` |
| `error_message` | String or null | Error details when `outcome` is `error` |
| `read_replica_used` | Boolean | `true` if the query ran on the read replica |
| `server_version` | String | Server version at time of invocation |

### Filtering Examples

**All calls by a specific caller:**

```bash
grep '"caller_id":"claude-agent"' log/wild_introspection_audit.jsonl | jq .
```

**All denied requests:**

```bash
grep '"outcome":"denied"' log/wild_introspection_audit.jsonl | jq .
```

**All calls to a specific tool:**

```bash
grep '"tool_name":"find_records_by_filter"' log/wild_introspection_audit.jsonl | jq .
```

**All timeouts:**

```bash
grep '"outcome":"timeout"' log/wild_introspection_audit.jsonl | jq .
```

**Calls with truncated results (hit row cap):**

```bash
grep '"truncated":true' log/wild_introspection_audit.jsonl | jq .
```

**Calls in the last hour (approximate, by timestamp prefix):**

```bash
grep '"timestamp":"2026-03-18T16' log/wild_introspection_audit.jsonl | jq .
```

### Reading a Single Record

```bash
tail -1 log/wild_introspection_audit.jsonl | jq .
```

Example output:

```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "timestamp": "2026-03-18T16:30:00Z",
  "caller_id": "claude-agent",
  "caller_type": "api_key",
  "tool_name": "find_records_by_filter",
  "model_name": "User",
  "parameters": {"field": "status", "value": "active"},
  "guard_result": "allowed",
  "outcome": "success",
  "duration_ms": 12,
  "rows_returned": 50,
  "truncated": true,
  "error_message": null,
  "read_replica_used": false,
  "server_version": "0.1.0"
}
```

### What to Look For

| Situation | What to Check |
|-----------|---------------|
| Suspected unauthorized access | Filter by `outcome: denied` and check `caller_id` values |
| Performance issues | Sort by `duration_ms` to find slow queries |
| Data exposure concerns | Filter by `model_name` and check `rows_returned` and `truncated` |
| Configuration errors | Filter by `outcome: error` and check `error_message` |
| Capacity planning | Count calls by `tool_name` to understand usage patterns |
