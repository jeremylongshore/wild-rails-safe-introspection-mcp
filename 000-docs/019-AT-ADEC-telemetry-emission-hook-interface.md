# Telemetry Emission Hook Interface — wild-rails-safe-introspection-mcp

**Document type:** Architecture decision record
**Filed as:** `019-AT-ADEC-telemetry-emission-hook-interface.md`
**Status:** Planned — interface definition only, not yet implemented
**Last updated:** 2026-03-18
**Epic:** 10 — Expansion Readiness
**Task:** 1cv.4 — Document the telemetry emission hook interface

---

## Purpose

This document defines the interface through which `wild-rails-safe-introspection-mcp` will emit usage events to `wild-session-telemetry` when that repo is ready to receive them. The goal is to make the emission boundary clear so both repos can develop independently and integrate later.

This is an **interface definition**, not an implementation. No code changes are required until `wild-session-telemetry` publishes its event ingestion contract.

---

## 1. Relationship to the Audit Trail

The audit trail and telemetry serve different purposes:

| Concern | Audit Trail | Telemetry |
|---------|------------|-----------|
| **Purpose** | Accountability — prove what was accessed, by whom, when | Observability — understand usage patterns, latency, capacity |
| **Audience** | Security reviewers, compliance, incident response | Platform operators, product teams, gap analysis |
| **Retention** | Long-term, append-only, immutable | Aggregatable, possibly time-windowed |
| **Granularity** | Per-invocation, full parameters | Per-invocation or aggregated, privacy-reduced |
| **Required?** | Yes — safety invariant (Doc 003, Rule 7) | No — optional operational enhancement |

**Key decision:** Telemetry does NOT replace or modify the audit trail. It is a separate, optional emission path. Disabling telemetry must not affect audit completeness. The audit trail remains the source of truth for security purposes.

---

## 2. What Gets Emitted

Telemetry events are derived from data already captured by the audit system. No new data collection is introduced — telemetry is a projection of existing audit data, filtered for privacy.

### 2.1 Event Types

| Event type | Trigger | Purpose |
|-----------|---------|---------|
| `tool_invocation` | Every tool call that completes (success, denial, error, timeout) | Track tool usage, latency, error rates |
| `server_startup` | MCP server starts | Track deployment frequency, configuration |
| `policy_loaded` | Access policy or blocked resources loaded at startup | Track policy state for audit correlation |

### 2.2 `tool_invocation` Event Schema

This is the primary telemetry event. It is emitted once per tool invocation, after the audit record is created.

```ruby
{
  event_type: "tool_invocation",
  timestamp: "2026-03-18T14:30:00.123Z",  # UTC ISO 8601
  server_version: "0.1.0",

  # Invocation metadata
  tool_name: "lookup_record_by_id",
  outcome: "success",                       # success | denied | timeout | error
  duration_ms: 42,

  # Resource metadata (non-identifying)
  model_name: "Account",                    # which model was targeted
  rows_returned: 1,
  truncated: false,

  # Caller metadata (privacy-reduced)
  caller_type: "api_key",                   # type, not identity
  authenticated: true,

  # Infrastructure metadata
  read_replica_used: true
}
```

**What is NOT in the telemetry event:**

| Excluded field | Reason |
|---------------|--------|
| `caller_id` | Privacy — telemetry should not carry individual identity |
| `parameters` | Privacy — filter values, record IDs are operational data, not telemetry |
| `guard_result` (raw) | Too detailed for telemetry — `outcome` is sufficient |
| `error_message` | May contain sensitive context — use `outcome: "error"` only |
| Record data | Never — telemetry carries metadata about invocations, not the data accessed |

### 2.3 `server_startup` Event Schema

```ruby
{
  event_type: "server_startup",
  timestamp: "2026-03-18T14:00:00.000Z",
  server_version: "0.1.0",
  tool_count: 3,
  allowed_model_count: 5,
  blocked_model_count: 3,
  read_replica_configured: true,
  capability_gate_mode: "stub"              # "stub" | "real"
}
```

### 2.4 `policy_loaded` Event Schema

```ruby
{
  event_type: "policy_loaded",
  timestamp: "2026-03-18T14:00:00.001Z",
  server_version: "0.1.0",
  allowed_models: ["Account", "User", "FeatureFlag"],   # names only, no config details
  blocked_model_count: 3,
  blocked_column_rule_count: 5,
  default_max_rows: 50,
  default_query_timeout_ms: 5000
}
```

---

## 3. Emission Interface

### 3.1 The Hook Point

Telemetry emission hooks into the existing `Audit::Recorder` flow. After the audit record is created and logged, the telemetry emitter receives a privacy-reduced projection.

```
Tool invocation
  → ToolHandler.execute
    → Audit::Recorder.record
      → AuditLogger.log(audit_record)        # existing — audit trail
      → TelemetryEmitter.emit(audit_record)   # new — telemetry hook
```

### 3.2 Emitter Interface

```ruby
module WildRailsSafeIntrospection
  module Telemetry
    module Emitter
      # Emit a telemetry event derived from an audit record.
      # Called after every tool invocation, after the audit record is logged.
      #
      # @param audit_record [Audit::AuditRecord] the completed audit record
      # @return [void]
      def self.emit(audit_record)
        return unless enabled?

        event = EventBuilder.build_tool_invocation(audit_record)
        deliver(event)
      end

      # Emit a server lifecycle event (startup, policy load).
      #
      # @param event [Hash] the telemetry event hash
      # @return [void]
      def self.emit_lifecycle(event)
        return unless enabled?

        deliver(event)
      end

      # Whether telemetry emission is enabled.
      # Controlled by configuration. Defaults to false.
      #
      # @return [Boolean]
      def self.enabled?
        WildRailsSafeIntrospection.configuration.telemetry_enabled
      end

      private_class_method def self.deliver(event)
        backend.deliver(event)
      end

      private_class_method def self.backend
        WildRailsSafeIntrospection.configuration.telemetry_backend
      end
    end
  end
end
```

### 3.3 Event Builder

The `EventBuilder` transforms an `AuditRecord` into a privacy-reduced telemetry event by stripping identity and parameter fields:

```ruby
module WildRailsSafeIntrospection
  module Telemetry
    module EventBuilder
      def self.build_tool_invocation(audit_record)
        {
          event_type: "tool_invocation",
          timestamp: audit_record.timestamp,
          server_version: audit_record.server_version,
          tool_name: audit_record.tool_name,
          outcome: audit_record.outcome,
          duration_ms: audit_record.duration_ms,
          model_name: audit_record.model_name,
          rows_returned: audit_record.rows_returned,
          truncated: audit_record.truncated,
          caller_type: audit_record.caller_type,
          authenticated: audit_record.caller_id != "anonymous",
          read_replica_used: audit_record.read_replica_used
        }
      end
    end
  end
end
```

Note: `caller_id` is deliberately not included. The telemetry event carries `caller_type` (the kind of credential) and `authenticated` (boolean) but not the specific caller identity.

### 3.4 Backend Interface

The delivery backend is pluggable. The emitter delegates to whatever backend is configured.

```ruby
module WildRailsSafeIntrospection
  module Telemetry
    module Backends
      # JSON Lines file backend (default, mirrors audit approach)
      module JsonlBackend
        def self.deliver(event)
          path = WildRailsSafeIntrospection.configuration.telemetry_log_path
          return unless path

          File.open(path, "a") { |f| f.puts(JSON.generate(event)) }
        end
      end

      # Null backend (telemetry disabled or not configured)
      module NullBackend
        def self.deliver(_event) = nil
      end
    end
  end
end
```

When `wild-session-telemetry` publishes its ingestion interface, a new backend will be added (e.g., `SessionTelemetryBackend`) that delivers events to the telemetry service via its documented API.

---

## 4. Configuration

Telemetry is opt-in. Default: disabled.

### 4.1 New Configuration Fields

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `telemetry_enabled` | Boolean | `false` | Master switch for telemetry emission |
| `telemetry_backend` | Module | `Backends::NullBackend` | Delivery backend (responds to `.deliver(event)`) |
| `telemetry_log_path` | String/nil | `nil` | File path for JSONL backend (only used by `JsonlBackend`) |

### 4.2 Configuration Example

```ruby
WildRailsSafeIntrospection.configure do |config|
  # ... existing config ...

  config.telemetry_enabled = true
  config.telemetry_backend = WildRailsSafeIntrospection::Telemetry::Backends::JsonlBackend
  config.telemetry_log_path = "log/introspection_telemetry.jsonl"
end
```

---

## 5. Privacy Model

Telemetry is designed to be privacy-reduced relative to the audit trail.

### 5.1 What telemetry knows

- Which tools are called and how often
- Which models are queried
- Latency distribution
- Error and denial rates
- Whether callers are authenticated (boolean, not who they are)
- Whether a read replica was used
- Server version and configuration summary

### 5.2 What telemetry does NOT know

- Who specific callers are (`caller_id` is stripped)
- What parameters were passed (filter values, record IDs stripped)
- What data was returned (record contents never appear)
- Why a specific denial occurred (just that it was denied)
- Detailed error messages

### 5.3 Privacy guarantee

The `EventBuilder` is the privacy boundary. It reads an `AuditRecord` and produces a telemetry event with strictly fewer fields. The telemetry event schema is defined positively (whitelist of fields to include), not negatively (blacklist of fields to exclude). This means new fields added to `AuditRecord` do NOT automatically flow to telemetry — they must be explicitly added to `EventBuilder`.

---

## 6. Integration Timeline

| Phase | What happens | Dependency |
|-------|-------------|------------|
| **Now** | Interface defined (this document) | None |
| **When implemented** | `Telemetry::Emitter`, `EventBuilder`, `Backends::JsonlBackend` added to this repo | None — can be implemented independently |
| **When `wild-session-telemetry` ships** | New backend added that delivers to the telemetry service | `wild-session-telemetry` publishes ingestion API |
| **When integrated** | `telemetry_enabled = true` with the session telemetry backend configured | Both repos stable |

### What blocks what

- This repo can implement the telemetry emission code at any time — it is self-contained
- The JSONL backend provides immediate local value (operators can analyze telemetry files)
- Integration with `wild-session-telemetry` requires that repo to define its event ingestion contract
- Neither repo blocks the other — they converge when both are ready

---

## 7. Safety Constraints

| Constraint | How it's satisfied |
|------------|-------------------|
| Telemetry must not affect audit trail | Emission is a separate call after `AuditLogger.log`, not a replacement |
| Telemetry failure must not break tool invocation | `Emitter.emit` should rescue all exceptions and log to stderr — tool invocations must not fail because telemetry is broken |
| Telemetry must not carry caller identity | `EventBuilder` strips `caller_id`, only emits `caller_type` and `authenticated` boolean |
| Telemetry must not carry parameters or data | `EventBuilder` strips `parameters`, `guard_result`, and `error_message` |
| Disabling telemetry must be trivial | `telemetry_enabled = false` (default) disables all emission with zero overhead |
| No new data collection | Telemetry is a projection of existing audit data, not a new instrumentation layer |

---

## 8. What This Document Does NOT Cover

- **The `wild-session-telemetry` ingestion API** — that repo defines its own contract
- **Telemetry aggregation, storage, or dashboards** — those are the telemetry repo's concern
- **Gap analysis from telemetry data** — that's `wild-gap-miner`'s concern
- **Real-time alerting** — not a v1 telemetry concern
- **Telemetry for admin operations** — `wild-admin-tools-mcp` will define its own emission interface

---

## Reference Documents

| Document | Relevance |
|----------|-----------|
| [001 — Blueprint, Section 9](001-PP-PLAN-repo-blueprint.md) | `wild-session-telemetry` relationship description |
| [003 — Safety Model, Rule 7](003-TQ-STND-safety-model.md) | Audit trail is mandatory — telemetry is separate |
| [005 — Threat Model, Threat 6](005-AT-ADEC-threat-model.md) | Audit bypass is a threat — telemetry must not create bypass paths |
| [018 — Architecture Extension Points, Section 5](018-AT-ADEC-architecture-extension-points.md) | Audit backend extension point that telemetry hooks alongside |
