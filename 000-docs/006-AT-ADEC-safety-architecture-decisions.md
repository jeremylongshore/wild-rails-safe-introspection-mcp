# Safety-Driven Architecture Decisions — wild-rails-safe-introspection-mcp

**Document type:** Architecture decision record
**Filed as:** `006-AT-ADEC-safety-architecture-decisions.md`
**Status:** Active
**Last updated:** 2026-03-17

---

## Purpose

The safety model implies specific architecture decisions. This document captures those decisions so they are explicit and reviewable rather than implicit in code.

---

## Decision 1: Model Resolution by Allowlist Hash, Not Constantize

**Context:** The adapter needs to resolve a model name string (e.g., `"Account"`) to an ActiveRecord class so it can query it.

**Options considered:**
- `model_name.constantize` — standard Rails pattern, resolves any class from a string
- `Object.const_get(model_name)` — same risk
- Explicit allowlist hash lookup — `MODELS["Account"] #=> Account`

**Decision:** Allowlist hash lookup.

**Rationale:** `constantize` and `const_get` resolve arbitrary constants, including classes that are not ActiveRecord models, internal framework classes, or classes with dangerous class methods. The allowlist hash is populated at startup from the policy config. Only models explicitly listed are resolvable. This closes the class resolution attack surface entirely.

**Trade-off:** Adding a new model requires updating the allowlist config and restarting. This is a feature, not a bug — it prevents accidental exposure.

---

## Decision 2: Database Credentials — Read-Only User Preferred, Application Guard Always

**Context:** The system needs database credentials. The strongest guarantee against writes is a read-only database user.

**Decision:** Use a read-only database user when available. Always enforce application-level write prevention regardless of credential type.

**Rationale:** Read-only credentials provide a structural guarantee at the database level. But not all infrastructure supports easily provisioning read-only users (e.g., some managed database services, development environments). The application guard provides defense-in-depth. When the DB credential is read-write, the application guard is the sole enforcement layer — this fallback is logged as an audit event so operators know the structural guarantee is not in effect.

**Configuration:** A `database_url` config value points to the read connection. The operator is responsible for ensuring it uses appropriate credentials.

---

## Decision 3: Read-Replica Fallback Behavior

**Context:** The system should route queries to a read replica when available. But not all environments have one.

**Decision:** Route to read replica when configured. Fall back to primary connection when no replica is configured. Log the fallback as an audit event on startup.

**Rationale:** Refusing to start without a replica would make the server unusable in development and testing environments. The fallback is acceptable because the safety model does not depend on the replica — it depends on the read-only credential and the application guard. The replica is a performance and isolation benefit, not a safety enforcement layer.

**Audit event on fallback:**
```json
{
  "event": "startup_warning",
  "message": "No read replica configured. Queries will use the primary connection.",
  "severity": "warning"
}
```

---

## Decision 4: Denial Response Format — Uniform, Non-Revealing

**Context:** When a request is denied, the response needs to tell the caller enough to be useful but not so much that it reveals information about the system's internal state.

**Decision:** All denial responses use the same structure. The denial reason is a category code, not a descriptive message about internal state. Blocked models and non-existent models produce the same response.

**Rationale:** If denied-because-blocked produces a different response than denied-because-nonexistent, an attacker can enumerate the model space by observing response differences. Uniform responses eliminate this information channel.

**Response structure:**
```json
{
  "status": "denied",
  "reason": "model_not_allowed | column_blocked | row_cap_exceeded | query_timeout | auth_required | auth_invalid",
  "tool": "tool_name",
  "timestamp": "ISO 8601"
}
```

Note: `column_blocked` is never returned as a denial — blocked columns are silently stripped. The `column_blocked` reason would only appear if a query requested *only* blocked columns and the result set would be empty.

---

## Decision 5: Audit Storage Backend — JSON Lines File (v1)

**Context:** Audit records need to be stored somewhere. Options include a database table, a JSON lines file, a structured log service, or a message queue.

**Decision:** JSON Lines file (`audit.jsonl`) in v1. One JSON object per line, append-only.

**Rationale:** A JSON Lines file is:
- Simple to implement (no additional infrastructure)
- Easy to inspect (`cat`, `jq`, `grep`)
- Append-only by nature (just open in append mode)
- Easy to ship to log aggregation later (tail the file)
- Not dependent on the Rails app's database (separates audit from data)

**Trade-off:** Not queryable like a database table. For v1, the volume of audit records is low enough that file-based storage is adequate. If volume or query needs grow, a later phase can add a database backend behind the same audit interface.

**Location:** Configurable via `audit_log_path`. Default: `log/introspection_audit.jsonl`.

---

## Decision 6: Single-Predicate Filter Constraint

**Context:** The `find_records_by_filter` tool needs a filter mechanism. Options range from a single field/value predicate to a full query builder with AND/OR/comparison operators.

**Decision:** v1 supports exactly one predicate: one field, one value, equality comparison only.

**Rationale:** A single-predicate filter is:
- Easy to validate (is this field on the model? is it an allowed column?)
- Easy to parameterize safely (`where(field => value)`)
- Hard to abuse (no OR-based full table scans, no subqueries)
- Sufficient for the v1 use cases ("find accounts in error state," "find users with this email")

**Trade-off:** Cannot express `created_at > '2026-01-01'` or `status IN ('active', 'trial')`. These require richer query support in v2. For v1, the constraint is acceptable because the primary use case is operational point lookups, not analytical filtering.

---

## Decision 7: No Dynamic Tool Generation

**Context:** The MCP tool catalog could be generated dynamically from the allowlist (one tool per model) or defined statically.

**Decision:** Static, explicitly defined tools. The v1 tool set is exactly three tools, defined in code, reviewed in the tool catalog doc.

**Rationale:** Dynamic tool generation from configuration is harder to audit, harder to test, and harder to reason about. If the allowlist changes, the tool surface changes — which means the safety boundary changes without explicit review. Static tools mean the tool surface is versioned with the code and reviewed in PRs.

**Trade-off:** Adding a new tool requires a code change and release, not just a config change. This is intentional — new tools should be reviewed, not auto-generated.
