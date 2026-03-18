# Blocked Resource Policy — wild-rails-safe-introspection-mcp

**Document type:** Safety standard
**Filed as:** `004-TQ-STND-blocked-resource-policy.md`
**Status:** Active — governing spec for policy enforcement
**Last updated:** 2026-03-17

---

## Purpose

This document defines the exact format, rules, and behavior of the allowlist and denylist policy system. It is the reference for implementing the query guard (Epic 4) and for operators who need to configure access policies for their Rails application.

---

## Policy Files

Two YAML files control access:

| File | Purpose | Location |
|------|---------|----------|
| `access_policy.yml` | Allowlist — which models and columns are accessible | `config/access_policy.yml` |
| `blocked_resources.yml` | Denylist — which models and columns are never accessible | `config/blocked_resources.yml` |

Both files are loaded at server startup. Changes require a server restart.

---

## Allowlist: `access_policy.yml`

### Format

```yaml
# config/access_policy.yml
#
# Models listed here are accessible through introspection tools.
# Models NOT listed here are refused — no exceptions.

version: 1

defaults:
  max_rows: 50                    # default per-query row cap
  query_timeout_ms: 5000          # default per-query timeout

allowed_models:
  # Expose all columns except those blocked by the denylist
  - name: Account
    columns: all_except_blocked
    max_rows: 100                 # override default for this model

  # Expose only explicitly listed columns
  - name: User
    columns:
      - id
      - email
      - name
      - status
      - created_at
      - updated_at

  # Expose all columns (use only for models with no sensitive data)
  - name: FeatureFlag
    columns: all

  # Expose with a custom timeout for a model known to have slow queries
  - name: Order
    columns: all_except_blocked
    query_timeout_ms: 10000
```

### Column access modes

| Mode | Meaning |
|------|---------|
| `all` | All columns accessible. Use only when the model has no sensitive data whatsoever. |
| `all_except_blocked` | All columns accessible except those listed in the denylist. This is the recommended default. |
| `[explicit list]` | Only the listed columns are accessible. Most restrictive. |

### Rules

1. If a model is not in `allowed_models`, it is refused
2. If `columns` is an explicit list, only those columns are returned — the denylist is still checked as a second layer
3. If `columns` is `all` or `all_except_blocked`, the denylist strips blocked columns
4. Per-model `max_rows` and `query_timeout_ms` override defaults when specified
5. An empty `allowed_models` list means nothing is accessible — this is the safe default

---

## Denylist: `blocked_resources.yml`

### Format

```yaml
# config/blocked_resources.yml
#
# Resources listed here are NEVER accessible, regardless of the allowlist.
# The denylist always takes precedence.

version: 1

blocked_models:
  # These models are completely inaccessible
  - CreditCard
  - ApiKey
  - SessionToken
  - OauthAccessToken
  - AuditLog
  - EncryptedCredential

blocked_columns:
  # Columns blocked on specific models
  - model: User
    columns:
      - password_digest
      - encrypted_password
      - otp_secret
      - recovery_codes
      - reset_password_token

  - model: Account
    columns:
      - stripe_customer_id
      - billing_token
      - tax_id
      - bank_account_number

  # Columns blocked on ALL models (wildcard)
  - model: "*"
    columns:
      - ssn
      - social_security_number
      - credit_card_number
      - cvv
      - encrypted_password
      - password_digest
      - secret_key
      - private_key
      - access_token
      - refresh_token
```

### Rules

1. A model in `blocked_models` is completely inaccessible — even if it appears in the allowlist
2. A column in `blocked_columns` is silently stripped from results — the response does not indicate the column was removed
3. Wildcard entries (`model: "*"`) apply to all models
4. Model-specific entries and wildcard entries are both applied — they are additive
5. The denylist is always evaluated after the allowlist — it can only restrict, never expand

---

## Precedence

```
Incoming request
  │
  ▼
Is model on allowlist?
  │  no → DENY (model_not_allowed)
  │  yes
  ▼
Is model on denylist blocked_models?
  │  yes → DENY (model_blocked)
  │  no
  ▼
Resolve accessible columns:
  1. Start with allowed columns (from allowlist entry)
  2. Remove any columns in blocked_columns for this model
  3. Remove any columns in blocked_columns for wildcard ("*")
  │
  ▼
Execute query with remaining columns only
```

---

## Validation

At server startup, the policy engine validates both files:

| Check | Failure behavior |
|-------|-----------------|
| YAML syntax valid | Server refuses to start |
| `version` field present and supported | Server refuses to start |
| No model appears in both `allowed_models` and `blocked_models` | Warning logged (denylist wins, but config is contradictory) |
| All column names in explicit lists exist on the model | Warning logged (non-existent columns are ignored) |
| At least one model in `allowed_models` | Warning logged (server starts but nothing is accessible) |

---

## Operator Workflow

### Adding a new model

1. Add the model name to `allowed_models` in `access_policy.yml`
2. Choose a column mode: `all`, `all_except_blocked`, or explicit list
3. Check `blocked_resources.yml` for any column overlaps
4. Restart the server
5. Verify access by calling `inspect_model_schema` for the new model

### Blocking a column retroactively

1. Add the column to `blocked_columns` in `blocked_resources.yml`
2. Restart the server
3. The column will be silently stripped from all future responses
4. No data already returned in past responses is recalled (audit trail records what was returned)

### Emergency lockdown

Set `allowed_models: []` in `access_policy.yml` and restart. The server will reject all model access requests immediately.

---

## Example: Complete Policy Set

A realistic policy for a mid-size Rails SaaS application:

```yaml
# access_policy.yml
version: 1
defaults:
  max_rows: 50
  query_timeout_ms: 5000

allowed_models:
  - name: Account
    columns: all_except_blocked
  - name: User
    columns: [id, email, name, role, status, created_at, updated_at, last_sign_in_at]
  - name: Subscription
    columns: all_except_blocked
  - name: FeatureFlag
    columns: all
  - name: Plan
    columns: all
  - name: BackgroundJob
    columns: [id, job_class, status, queue, created_at, updated_at, error_message]
```

```yaml
# blocked_resources.yml
version: 1
blocked_models:
  - CreditCard
  - ApiKey
  - SessionToken
  - AuditLog

blocked_columns:
  - model: User
    columns: [password_digest, otp_secret, recovery_codes]
  - model: Account
    columns: [stripe_customer_id, tax_id]
  - model: "*"
    columns: [ssn, credit_card_number, encrypted_password, secret_key, access_token]
```
