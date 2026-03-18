# Capability Gate Integration Plan — wild-rails-safe-introspection-mcp

**Document type:** Architecture decision record
**Filed as:** `016-AT-ADEC-capability-gate-integration-plan.md`
**Status:** Planned — execute only after `wild-capability-gate` gem is published
**Last updated:** 2026-03-18
**Epic:** 10 (Expansion Readiness)
**Task:** 1cv.1

---

## Purpose

This document describes how to replace the v1 stub `Identity::CapabilityGate` with a real integration against the `wild-capability-gate` gem. It maps the stub interface to the gate's public API, specifies configuration, and defines the safety constraints that must hold through the transition.

This is a **plan**, not an implementation. Do not execute until the gate gem is published and versioned.

---

## 1. Current Stub Interface

Defined in `lib/wild_rails_safe_introspection/identity/capability_gate.rb` and documented in Doc 009.

```ruby
Identity::CapabilityGate.permitted?(request_context, action:, resource:) # => Boolean
Identity::CapabilityGate.denial_response                                 # => Hash
```

**Stub behavior:** Returns `request_context.authenticated?` — every authenticated caller is permitted every action on every resource. No configuration. No prerequisites. No per-action grants.

**Actions defined in v1:**

| Action | Tool |
|--------|------|
| `inspect_model_schema` | Schema introspection |
| `lookup_record_by_id` | Single record lookup |
| `find_records_by_filter` | Filtered record search |

---

## 2. Real Gate Interface

Defined in `wild-capability-gate` Doc 006 (interface contract) and Doc 010 (consumer integration guide).

```ruby
# Initialization (once at boot)
gate = Wild::CapabilityGate.new(
  config_path: "config/capability_gate",
  audit_log_path: "log/capability_gate.jsonl",
  session_id: SecureRandom.uuid
)

# Evaluation (per request)
result = gate.evaluate(
  caller: "service-account:introspection-agent",
  capability: :inspect_model_schema,
  context: {}
)

result.allowed?   # => true or false
result.denied?    # => true or false
result.reason     # => nil, :unknown_capability, :not_granted, :prerequisite_not_met, :evaluation_error
result.details    # => nil or String
```

**Key differences from stub:**

| Aspect | Stub | Real gate |
|--------|------|-----------|
| Granularity | All-or-nothing (authenticated = permitted) | Per-capability, per-caller grants |
| Configuration | None | `capabilities.yml` + `grants.yml` |
| Prerequisites | None | Enforced per-capability |
| Return type | Boolean | `EvaluationResult` object |
| Audit | Handled by caller | Built-in audit log |
| Fail behavior | Returns `authenticated?` | Fail-closed (errors = denial) |

---

## 3. Interface Mapping

The integration must translate between the stub's `(request_context, action:, resource:)` signature and the gate's `(caller:, capability:, context:)` signature.

### 3.1 Caller identity

```
request_context.caller_id  →  gate.evaluate(caller: ...)
```

The `RequestContext` already carries a `caller_id` string (from API key lookup). This maps directly to the gate's opaque caller identity string. No transformation needed.

**Convention to adopt:** Use the pattern `"mcp-client:<caller_id>"` to namespace MCP callers within the gate's grant configuration.

### 3.2 Action to capability

```
action:  →  capability:
```

The stub's `action` strings map 1:1 to capability names. Define one capability per tool action in `capabilities.yml`:

```yaml
capabilities:
  - name: inspect_model_schema
    description: "Read-only schema inspection for a single model"
    risk_level: standard
    prerequisites: []

  - name: lookup_record_by_id
    description: "Single record lookup by primary key"
    risk_level: standard
    prerequisites: []

  - name: find_records_by_filter
    description: "Filtered record search with row cap"
    risk_level: standard
    prerequisites: []
```

### 3.3 Resource as context

```
resource:  →  context: { "resource" => resource }
```

The stub's `resource:` parameter (e.g., model name) becomes part of the gate's optional `context` hash. In v1 of the gate, context is used for prerequisite evaluation — it does not filter grants by resource. Per-resource grants would require a gate v2 feature. For now, pass the resource as context for audit trail enrichment.

### 3.4 Result translation

The stub returns a boolean. The gate returns an `EvaluationResult`. The `permitted?` method must translate:

```ruby
result = @gate.evaluate(caller: ..., capability: ..., context: ...)
result.allowed?  # replaces request_context.authenticated?
```

---

## 4. Implementation Changes

### 4.1 Add gem dependency

In `Gemfile`:

```ruby
gem 'wild-capability-gate', path: '../wild-capability-gate'
```

When the gate gem is published to RubyGems, replace `path:` with a version constraint.

### 4.2 Add configuration files

Create in the consuming repo:

```
config/capability_gate/
  capabilities.yml    # Capability definitions (see Section 3.2)
  grants.yml          # Caller-to-capability grants
```

Starter `grants.yml` — mirrors the stub's "all authenticated callers permitted" behavior:

```yaml
grants:
  - caller: "*"
    capabilities:
      - inspect_model_schema
      - lookup_record_by_id
      - find_records_by_filter
```

Operators can then tighten grants per-caller as needed.

### 4.3 Initialize gate at boot

Add a gate initializer that runs once when the MCP server starts:

```ruby
# In server initialization
require 'wild/capability_gate'

CAPABILITY_GATE = Wild::CapabilityGate.new(
  config_path: File.join(config_root, "capability_gate"),
  audit_log_path: File.join(log_root, "capability_gate.jsonl"),
  session_id: SecureRandom.uuid
)
```

If config is invalid, this raises at startup — fail-fast, not fail-per-request.

### 4.4 Replace stub logic

In `lib/wild_rails_safe_introspection/identity/capability_gate.rb`:

```ruby
module WildRailsSafeIntrospection
  module Identity
    module CapabilityGate
      class << self
        attr_accessor :gate_instance

        def permitted?(request_context, action:, resource: nil)
          return false unless request_context.authenticated?

          result = gate_instance.evaluate(
            caller: "mcp-client:#{request_context.caller_id}",
            capability: action.to_sym,
            context: resource ? { "resource" => resource } : {}
          )

          result.allowed?
        end

        def denial_response
          CAPABILITY_DENIAL
        end
      end
    end
  end
end
```

**Critical:** The `permitted?` method signature does not change. All existing call sites continue to call `CapabilityGate.permitted?(request_context, action:, resource:)`. The change is internal only.

**Safety note:** The `authenticated?` check is preserved as a pre-condition. Even if the gate somehow grants an unauthenticated caller, the identity layer rejects first. Defense in depth.

### 4.5 Wire initialization

Set `CapabilityGate.gate_instance = CAPABILITY_GATE` during server boot, after the gate is constructed.

---

## 5. Safety Constraints

These must hold before, during, and after integration:

| Constraint | How it's preserved |
|------------|-------------------|
| Fail-closed | Gate returns denial on any error. Stub's `authenticated?` check remains as pre-guard. |
| Audit trail | Gate writes its own audit log. Existing invocation audit in the MCP server layer is unchanged. |
| No signature change | `permitted?` keeps `(request_context, action:, resource:)`. Zero call-site changes. |
| Denial response format | `CAPABILITY_DENIAL` hash is unchanged. Tool handlers still receive the same structure. |
| Startup validation | Invalid config raises at initialization, not at evaluation time. |

### 5.1 What could go wrong

| Risk | Mitigation |
|------|-----------|
| Gate gem not on load path | `require 'wild/capability_gate'` fails at boot — immediate, visible error |
| Config files missing | Gate raises at initialization — caught before any request is served |
| Caller ID format mismatch | Use consistent `"mcp-client:<id>"` pattern; document in grants.yml |
| Gate denies previously-permitted callers | Start with wildcard grants to match stub behavior; tighten incrementally |
| Performance regression | Gate evaluation is in-memory YAML lookup — microseconds, not a concern |

---

## 6. Testing Requirements

### 6.1 Tests to add

1. **Gate integration smoke test** — initialize gate with test config, evaluate known caller + capability, assert allowed
2. **Denial test** — evaluate unknown capability, assert denied with correct reason
3. **Unauthenticated bypass test** — unauthenticated request_context is denied even if gate would allow (defense in depth)
4. **Config validation test** — invalid config raises at initialization
5. **Audit emission test** — evaluation produces audit log entry

### 6.2 Tests that must not break

All 468 existing tests must pass unchanged. The integration is internal to `CapabilityGate.permitted?` — no test should need modification if the stub's external behavior is preserved during the transition.

### 6.3 Transition testing strategy

1. Deploy with wildcard grants first (matches stub behavior exactly)
2. Run full test suite — all 468 must pass
3. Tighten grants incrementally, verifying denials work correctly
4. Only then remove the wildcard grant

---

## 7. Execution Sequence

Do NOT execute this plan until:

- [ ] `wild-capability-gate` gem is published (path reference or RubyGems)
- [ ] Gate gem passes its own 224 tests on the version being integrated
- [ ] This plan has been reviewed for any gate API changes since this doc was written

When ready, execute in this order:

1. Create feature branch
2. Add gem dependency, run `bundle install`
3. Add `config/capability_gate/` with capabilities and wildcard grants
4. Add gate initializer
5. Replace stub logic (Section 4.4)
6. Wire initialization (Section 4.5)
7. Add new tests (Section 6.1)
8. Run full test suite (must pass all 468 + new tests)
9. Run rubocop
10. Update Doc 009 to mark integration as complete
11. Update this document status to "Implemented"

---

## 8. What This Plan Does NOT Cover

- **Per-resource grants** — the gate v1 does not support resource-scoped grants. If needed, that's a gate v2 feature.
- **Dynamic capability registration** — capabilities are static YAML. Runtime registration is out of scope.
- **Gate UI or dashboard** — the gate is a library. Operator visibility is through audit logs and config inspection.
- **Multi-gate instances** — one gate instance per MCP server process. Sharding is not planned.
- **HTTP transport for the gate** — the gate is an in-process library, not a service call.
