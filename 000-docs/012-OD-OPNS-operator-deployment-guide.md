# Operator Deployment Guide — wild-rails-safe-introspection-mcp

**Document type:** Operations guide
**Filed as:** `012-OD-OPNS-operator-deployment-guide.md`
**Status:** Active
**Last updated:** 2026-03-18
**Epic:** 9 — Package the MVP

---

## Purpose

This guide walks a Rails platform engineer through deploying `wild-rails-safe-introspection-mcp` — a read-only MCP server that lets AI agents inspect your Rails application's data safely.

You do not need to have read the codebase. Follow these steps in order.

---

## Prerequisites

- A running Rails application using **Rails 7.0+** with ActiveRecord
- **Ruby >= 3.2.0**
- A database your Rails app already connects to (PostgreSQL, MySQL, or SQLite)
- Familiarity with your application's models and which ones contain sensitive data

---

## Step 1: Install the Gem

Add to your application's `Gemfile`:

```ruby
gem 'wild-rails-safe-introspection-mcp', '~> 0.1'
```

Run:

```bash
bundle install
```

This installs the gem and its dependencies (`activerecord >= 7.0`, `mcp ~> 0.8`).

---

## Step 2: Create the Access Policy

The access policy defines which models agents can see and which columns are exposed.

Create `config/wild_introspection/access_policy.yml`:

```yaml
version: 1

defaults:
  max_rows: 50
  query_timeout_ms: 5000

allowed_models:
  # Option A: Expose all columns except those on the denylist
  - name: Account
    columns: all_except_blocked
    max_rows: 100

  # Option B: Expose only specific columns (most restrictive, recommended for user models)
  - name: User
    columns:
      - id
      - email
      - name
      - status
      - created_at
      - updated_at

  # Option C: Expose all columns (use only for models with no sensitive data)
  - name: FeatureFlag
    columns: all
```

**Key rules:**

- Only models listed here are accessible. Everything else is denied.
- `max_rows` caps how many records a single query can return (hard ceiling: 1000).
- `query_timeout_ms` caps how long a single query can run (hard ceiling: 30,000ms, floor: 100ms).
- Use `columns: all_except_blocked` for models where you want most columns but need to hide specific ones.
- Use explicit column lists for models with many sensitive columns.

---

## Step 3: Create the Blocked Resources File

The blocked resources file defines models and columns that must never be exposed, even if accidentally added to the access policy.

Create `config/wild_introspection/blocked_resources.yml`:

```yaml
version: 1

blocked_models:
  - CreditCard
  - ApiKey
  - SessionToken
  - OauthAccessToken

blocked_columns:
  # Block specific columns on specific models
  - model: User
    columns:
      - password_digest
      - encrypted_password
      - otp_secret
      - reset_password_token

  - model: Account
    columns:
      - stripe_customer_id
      - tax_id

  # Block columns on ALL models (wildcard)
  - model: "*"
    columns:
      - ssn
      - credit_card_number
      - encrypted_password
```

**Key rules:**

- Blocked models override the access policy — even if `CreditCard` appears in `allowed_models`, it will be rejected.
- Wildcard blocked columns (`model: "*"`) apply to every model.
- Blocked column names are stripped from schema responses, record data, and filter results.
- Blocked column values never appear in any response, including raw JSON.

---

## Step 4: Generate API Keys

Each AI agent connecting to the server needs an API key. Generate keys that are at least 32 characters:

```bash
ruby -e "require 'securerandom'; puts \"sk-wild-#{SecureRandom.hex(24)}\""
```

You will configure these keys in the next step. Store them securely — treat them like database credentials.

---

## Step 5: Configure and Initialize the Server

Create an initializer in your Rails app. Create `config/initializers/wild_introspection.rb`:

```ruby
WildRailsSafeIntrospection.configure do |config|
  config.access_policy_path = Rails.root.join(
    'config/wild_introspection/access_policy.yml'
  ).to_s

  config.blocked_resources_path = Rails.root.join(
    'config/wild_introspection/blocked_resources.yml'
  ).to_s

  # Optional: enable audit logging (recommended for production)
  config.audit_log_path = Rails.root.join('log/wild_introspection_audit.jsonl').to_s

  # API keys for agent authentication
  config.api_keys = [
    { name: 'claude-agent', key: ENV.fetch('WILD_INTROSPECTION_API_KEY') }
  ]
end
```

**Important:** Store API keys in environment variables, not in the initializer file. Never commit API keys to source control.

---

## Step 6: Create the Server Entry Point

Create a script that starts the MCP server. Create `bin/wild_introspection_server`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../config/environment' # loads Rails and the initializer

server = WildRailsSafeIntrospection::Server::ServerFactory.create(
  server_context: { api_key: ENV.fetch('WILD_INTROSPECTION_API_KEY') }
)

server.run
```

Make it executable:

```bash
chmod +x bin/wild_introspection_server
```

The server communicates over **stdio** using the MCP protocol (JSON-RPC 2.0). It does not open an HTTP port. The MCP host (e.g., Claude Desktop, Claude Code) manages the transport.

---

## Step 7: Verify the Server Starts

Run the server manually to confirm configuration loads without errors:

```bash
WILD_INTROSPECTION_API_KEY=sk-wild-your-key-here \
  bundle exec ruby bin/wild_introspection_server
```

**What a successful start looks like:** The process starts without output and waits for MCP commands on stdin. No errors printed to stderr.

**Common startup errors and fixes:**

| Error | Cause | Fix |
|-------|-------|-----|
| `ConfigError: access_policy_path is required` | Path not set in initializer | Set `config.access_policy_path` |
| `ConfigError: access_policy not found: /path` | File doesn't exist at that path | Check the path; create the YAML file |
| `ConfigError: access_policy.yml must contain a version field` | Missing `version: 1` at top of YAML | Add `version: 1` as the first line |
| `ConfigError: blocked_resources_path is required` | Path not set in initializer | Set `config.blocked_resources_path` |
| `NameError` for a model in `allowed_models` | Model class not loaded when config loads | Ensure Rails eager-loads models before the initializer runs, or use `Rails.application.config.after_initialize` |

---

## Step 8: Connect to an MCP Host

### Claude Desktop

Add to your Claude Desktop MCP configuration (`~/.config/claude/claude_desktop_config.json` or equivalent):

```json
{
  "mcpServers": {
    "rails-introspection": {
      "command": "bundle",
      "args": ["exec", "ruby", "bin/wild_introspection_server"],
      "cwd": "/path/to/your/rails/app",
      "env": {
        "WILD_INTROSPECTION_API_KEY": "sk-wild-your-key-here"
      }
    }
  }
}
```

### Claude Code

Add to your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "rails-introspection": {
      "command": "bundle",
      "args": ["exec", "ruby", "bin/wild_introspection_server"],
      "cwd": "/path/to/your/rails/app",
      "env": {
        "WILD_INTROSPECTION_API_KEY": "sk-wild-your-key-here"
      }
    }
  }
}
```

### Verifying the Connection

Once connected, the MCP host should discover three tools:

1. **`inspect_model_schema`** — inspect a model's columns, types, and associations
2. **`lookup_record_by_id`** — look up a single record by primary key
3. **`find_records_by_filter`** — find records matching a field/value filter

Ask the AI agent to inspect a model you allowed:

> "Use the inspect_model_schema tool to show me the Account model schema."

If it returns column names and types, the server is working correctly.

---

## Step 9: Verify Safety Controls

After the server is running, verify the safety controls are working:

### Test 1: Blocked model is denied

Ask the agent to inspect a model on your blocked list. The response should be a denial with no information about whether the model exists.

### Test 2: Blocked columns are hidden

Ask the agent to look up a record from an allowed model that has blocked columns. The response should include only the allowed columns — no blocked column names or values.

### Test 3: Non-allowed model is denied

Ask the agent to inspect a model not on the allowlist. The response should be identical to the blocked model denial.

### Test 4: Audit log is recording

Check the audit log file:

```bash
tail -5 log/wild_introspection_audit.jsonl | python3 -m json.tool
```

Each line is a JSON record containing: `tool_name`, `model_name`, `caller_id`, `outcome`, `duration_ms`, `rows_returned`, `truncated`.

---

## Optional: Read Replica Configuration

For production deployments, route all introspection queries to a read replica:

```ruby
WildRailsSafeIntrospection::Adapter::ConnectionManager.configure(
  replica_url: ENV.fetch('DATABASE_REPLICA_URL')
)
```

Add this after the `configure` block in your initializer. When a replica URL is configured, all queries go to the replica. When it is not configured, queries use the application's primary ActiveRecord connection.

**Recommendation:** Use a read replica in production. This provides a structural guarantee that the introspection server cannot affect your primary database, even if a bug bypassed the application-level read-only guard.

---

## Configuration Quick Reference

| Parameter | Location | Required | Default |
|-----------|----------|----------|---------|
| `access_policy_path` | Initializer | Yes | — |
| `blocked_resources_path` | Initializer | Yes | — |
| `audit_log_path` | Initializer | No | `nil` (no logging) |
| `api_keys` | Initializer | Yes (at least one) | `[]` |
| `defaults.max_rows` | access_policy.yml | No | 50 |
| `defaults.query_timeout_ms` | access_policy.yml | No | 5000 |
| Per-model `max_rows` | access_policy.yml | No | inherits default |
| Per-model `query_timeout_ms` | access_policy.yml | No | inherits default |
| Replica URL | `ConnectionManager.configure` | No | uses primary |

**Hard limits (cannot be overridden):**

| Limit | Value |
|-------|-------|
| Maximum rows per query | 1,000 |
| Maximum query timeout | 30,000ms |
| Minimum query timeout | 100ms |

---

## Security Considerations

1. **API keys are secrets.** Store them in environment variables or a secrets manager. Never commit them to source control.
2. **The access policy is your attack surface.** Every model you add to the allowlist is visible to any agent with a valid API key. Start restrictive and expand.
3. **Audit logging should be enabled in production.** Without it, you cannot investigate what agents accessed.
4. **Use a read replica when available.** This provides defense-in-depth beyond the application-level read-only guard.
5. **Review the blocked resources file regularly.** When you add new models with sensitive columns, update the denylist.
6. **The server runs with your Rails app's database credentials.** The application-level guard prevents writes, but a read replica with read-only credentials provides a stronger guarantee.

---

## Next Steps

- **Configuration reference:** See `013-DR-REFF-configuration-reference.md` for every parameter in detail
- **Operator workflows:** See `014-OD-GUID-operator-workflow-guide.md` for adding models, blocking columns, revoking access
- **Safety model:** See `003-TQ-STND-safety-model.md` for the governing safety specification
- **Evaluation strategy:** See `011-TQ-SECU-evaluation-strategy.md` for the release testing protocol
