# 013 — Configuration Reference

**Category:** DR — Documentation & Reference
**Type:** REFF — Reference document
**Status:** v1

Complete reference for every configurable parameter in wild-rails-safe-introspection-mcp.

---

## 1. Initializer Parameters

These are set in a Rails initializer via `WildRailsSafeIntrospection.configure`:

```ruby
# config/initializers/wild_introspection.rb
WildRailsSafeIntrospection.configure do |config|
  config.access_policy_path    = Rails.root.join('config/wild_introspection/access_policy.yml').to_s
  config.blocked_resources_path = Rails.root.join('config/wild_introspection/blocked_resources.yml').to_s
  config.audit_log_path         = Rails.root.join('log/wild_introspection_audit.jsonl').to_s
  config.api_keys               = [{ name: 'claude-agent', key: ENV.fetch('WILD_INTROSPECTION_API_KEY') }]
end
```

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `access_policy_path` | String (file path) | `nil` | Yes | Path to the access policy YAML file. Must exist on disk. |
| `blocked_resources_path` | String (file path) | `nil` | Yes | Path to the blocked resources YAML file. Must exist on disk. |
| `audit_log_path` | String (file path) | `nil` | No | Path to the JSONL audit log file. Created automatically if missing. When `nil`, audit logging is disabled. |
| `api_keys` | Array of `{name:, key:}` hashes | `[]` | Yes (at least one) | API keys for caller authentication. Keys are compared using constant-time comparison. |

**Safety warnings:**

- **`audit_log_path`**: Production deployments should always enable audit logging. Without it, there is no record of who accessed what.
- **`api_keys`**: If the array is empty, all calls are rejected. Every key must have both `name` and `key` fields.

---

## 2. Replica Connection

Configured separately via `ConnectionManager.configure`:

```ruby
WildRailsSafeIntrospection::Adapter::ConnectionManager.configure(
  replica_url: ENV.fetch('DATABASE_REPLICA_URL', nil)
)
```

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `replica_url` | String (database URL) | `nil` | No | Database URL for a read-only replica. When `nil`, queries use the primary `ActiveRecord::Base.connection`. |

**Safety warning:** Production deployments should use a read replica with read-only database credentials. This provides defense-in-depth: even if application-level read-only guards were bypassed, the database connection itself prevents writes.

---

## 3. Access Policy File Format

File: `access_policy.yml` (path set via `access_policy_path`)

```yaml
version: 1

defaults:
  max_rows: 50
  query_timeout_ms: 5000

allowed_models:
  - name: Account
    columns: all_except_blocked
    max_rows: 100

  - name: User
    columns:
      - id
      - email
      - name
      - status
      - created_at
      - updated_at

  - name: FeatureFlag
    columns: all
```

### Top-Level Keys

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `version` | Integer | Yes | Must be `1`. Validated on load. |
| `defaults` | Hash | No | Global defaults for row caps and timeouts. |
| `allowed_models` | Array | No | List of model entries. Models not listed here are denied. |

### Defaults Section

| Parameter | Type | Default | Hard Floor | Hard Ceiling | Description |
|-----------|------|---------|------------|--------------|-------------|
| `max_rows` | Integer | 50 | 1 | 1000 | Maximum rows returned per query. Values outside the range are clamped. |
| `query_timeout_ms` | Integer | 5000 | 100 | 30000 | Query timeout in milliseconds. Values outside the range are clamped. |

### Model Entry Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | String | Yes | Ruby class name. Must match pattern `/\A[A-Z][A-Za-z0-9]*(::[A-Z][A-Za-z0-9]*)*\z/`. Namespaced models use `::` (e.g., `Billing::Invoice`). |
| `columns` | String or Array | Yes | Column exposure mode. See Section 5 below. |
| `max_rows` | Integer | No | Per-model row cap override. Inherits from `defaults.max_rows` if omitted. Subject to same hard limits (1–1000). |
| `query_timeout_ms` | Integer | No | Per-model timeout override. Inherits from `defaults.query_timeout_ms` if omitted. Subject to same hard limits (100–30000). |

**Safety warnings:**

- `max_rows`: Increasing this widens data exposure per query. The hard ceiling of 1000 cannot be exceeded — values above 1000 are silently clamped.
- `query_timeout_ms`: Increasing allows longer-running queries. The hard ceiling of 30000 ms cannot be exceeded. Values below 100 ms are clamped up to 100 ms.
- `name`: Must exactly match a loaded Ruby constant. If the class doesn't exist at load time, the model is silently skipped (no registry entry, no error).

---

## 4. Blocked Resources File Format

File: `blocked_resources.yml` (path set via `blocked_resources_path`)

```yaml
version: 1

blocked_models:
  - CreditCard
  - ApiKey

blocked_columns:
  - model: User
    columns:
      - password_digest
      - otp_secret

  - model: Account
    columns:
      - stripe_customer_id
      - tax_id

  - model: "*"
    columns:
      - ssn
      - credit_card_number
```

### Top-Level Keys

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `version` | Integer | Yes | Must be `1`. Validated on load. |
| `blocked_models` | Array of Strings | No | Model names to deny entirely. Overrides the allowlist — a model on both lists is denied. |
| `blocked_columns` | Array of Hashes | No | Column block entries. Blocked columns are silently stripped from all responses. |

### Blocked Column Entry Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `model` | String | Yes | Model name, or `"*"` for a wildcard that applies to all models. |
| `columns` | Array of Strings | Yes | Column names to block. Case-sensitive. |

**Key behaviors:**

- `blocked_models` takes absolute precedence over `allowed_models`. If a model appears on both lists, it is denied.
- Blocked columns are stripped silently — the caller receives no indication that columns were removed.
- Wildcard (`"*"`) column blocks apply to every model, including models with `columns: all`.
- Model-specific and wildcard blocks are combined (union) for each model.

---

## 5. Column Exposure Modes

The `columns` field on each model entry controls which columns are visible to callers.

| Mode | YAML Value | Behavior |
|------|------------|----------|
| **All except blocked** | `"all_except_blocked"` (or any unrecognized string) | Exposes all columns on the model *except* those in `blocked_columns` for that model and wildcards. This is the default when the value is unrecognized. |
| **All** | `"all"` | Exposes every column on the model, including columns that would normally be blocked by model-specific entries in `blocked_columns`. Wildcard (`"*"`) blocks are still applied. |
| **Explicit** | `["id", "email", "name"]` (Array) | Exposes only the listed columns. Blocked columns in the explicit list are still stripped. |

**Safety warning:** Using `columns: all` bypasses model-specific denylist entries for that model. Only use this for models with no sensitive columns. Wildcard blocks still apply regardless of mode.

---

## 6. Hard Limits and Clamping

All numeric parameters are automatically clamped during configuration load. Operators cannot exceed these limits regardless of what they set in YAML.

| Parameter | Minimum | Maximum | Clamping Behavior |
|-----------|---------|---------|-------------------|
| `max_rows` | 1 | 1000 | Values below 1 become 1. Values above 1000 become 1000. Applied to both defaults and per-model overrides. |
| `query_timeout_ms` | 100 | 30000 | Values below 100 become 100. Values above 30000 become 30000. Applied to both defaults and per-model overrides. |

Clamping is silent — no error or warning is raised. The clamped value is used.

**Constants (from `Configuration`):**

```ruby
HARD_ROW_CEILING       = 1000
HARD_TIMEOUT_CEILING_MS = 30_000
MINIMUM_TIMEOUT_MS     = 100
```

---

## 7. Configuration Lifecycle

1. **`WildRailsSafeIntrospection.configure`** yields a `Configuration` instance.
2. **`configuration.load!`** is called automatically after the block completes:
   - Validates that both policy file paths are set and exist on disk.
   - Loads and parses `access_policy.yml` — merges defaults, extracts allowed model entries.
   - Loads and parses `blocked_resources.yml` — freezes blocked model and column lists.
   - Clamps all numeric values to hard limits.
   - Resolves model names to Ruby constants via `Object.const_get` and builds the model registry.
   - Freezes all internal data structures. Configuration is immutable after this point.
3. **Post-load:** All policy data is frozen. No runtime modifications are possible.

**Errors during load:**

| Condition | Error |
|-----------|-------|
| `access_policy_path` not set | `ConfigError: access_policy_path is required` |
| `blocked_resources_path` not set | `ConfigError: blocked_resources_path is required` |
| Policy file does not exist | `ConfigError: <label> not found: <path>` |
| YAML missing `version` field | `ConfigError: <filename> must contain a version field` |

---

## 8. Safety Warnings Summary

| Topic | Warning |
|-------|---------|
| Audit logging | Enable `audit_log_path` in production. Without it, there is no invocation trail. |
| API keys | An empty `api_keys` array means all calls are rejected. Ensure at least one key is configured. |
| Read replica | Use `replica_url` in production for defense-in-depth write protection. |
| `columns: all` | Bypasses model-specific blocked columns. Only use for models with no sensitive data. |
| `max_rows` increases | Higher caps expose more data per query. Hard ceiling is 1000. |
| `query_timeout_ms` increases | Higher timeouts allow longer-running queries that may impact database performance. Hard ceiling is 30000 ms. |
| Model name resolution | Invalid or unresolvable model names are silently skipped. Verify your models are loaded before the initializer runs. |
| Frozen after load | Configuration cannot be changed at runtime. Any changes require a server restart. |
