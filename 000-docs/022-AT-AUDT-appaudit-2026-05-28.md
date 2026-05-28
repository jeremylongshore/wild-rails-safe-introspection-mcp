# Operator-Grade Audit — wild-rails-safe-introspection-mcp

**Document type:** Operator audit (appaudit)
**Filed as:** `022-AT-AUDT-appaudit-2026-05-28.md`
**Audit date:** 2026-05-28
**Auditor:** Claude Code (sole-eyes operator pass)
**Audience:** senior Rails/Ruby engineer, first read, must operate under stress in ten minutes
**Status:** Snapshot — v0.1.0 (`lib/wild_rails_safe_introspection/version.rb`), 10/10 epics closed per `000-docs/021-RL-REPT-release-v0.1.0.md`

---

## 1. Mission & Boundaries

This repo is one of ten in the `wild-*` ecosystem (`../CLAUDE.md`). Its single, narrow job is to be the **read-only, governed, MCP-fronted reflection surface** of a live Rails application. An AI agent should be able to ask "what does the `Account` model look like" or "give me the record with id 42" through three MCP tools, get back JSON, and never get anywhere near a Rails console, a write path, or an admin verb. Admin/mutation work explicitly lives in a sibling repo (`wild-admin-tools-mcp`); this repo refuses to host any of it. The split is enforced in the repo-level `CLAUDE.md` lines 18–24 ("What This Repo Does NOT Do") and again in the canonical out-of-scope ledger at `000-docs/020-PP-PLAN-confirmed-out-of-scope.md` §1 ("Permanent Boundaries").

The mission is governed by a tight stack of standards docs filed in `000-docs/`:

| Doc | Role |
|---|---|
| `003-TQ-STND-safety-model.md` | Ten enforceable safety rules. The code is wrong if it contradicts this doc (line 12). |
| `004-TQ-STND-blocked-resource-policy.md` | YAML format and precedence of allowlist/denylist. |
| `005-AT-ADEC-threat-model.md` | Seven named threats with mitigation + verification requirements. |
| `006-AT-ADEC-safety-architecture-decisions.md` | Seven architecture choices forced by the safety model. |
| `010-DR-REFF-tool-catalog.md` | Three v1 MCP tools, their schemas, and the "trust pipeline" diagram. |
| `020-PP-PLAN-confirmed-out-of-scope.md` | The "Does NOT do" ledger, consolidated. |

The **"Does NOT do" discipline** preserved across these docs is the load-bearing thing in this codebase. There are five permanent boundaries that the audit confirms hold structurally, not just by convention:

1. **No write operations.** Enforced by name-list in `lib/wild_rails_safe_introspection/adapter/write_prevention.rb` lines 6–19 (`FORBIDDEN_METHODS`) and by SQL pattern at line 21 (`WRITE_SQL_PATTERN`).
2. **No arbitrary Ruby execution.** No `eval`, no `send` with user input, no `constantize` of user input — verified by reading every file under `lib/`. Model resolution is hash lookup only (`lib/wild_rails_safe_introspection/adapter/model_resolver.rb` line 7, `lib/wild_rails_safe_introspection/configuration.rb` lines 108–114).
3. **No admin actions.** No code path opens transactions, enqueues jobs, clears caches, or writes flags. The closest you get to mutation is `ConnectionManager.establish_replica` (`lib/wild_rails_safe_introspection/adapter/connection_manager.rb` line 35), which is connection-pool setup at boot, not data mutation.
4. **No analytics/reporting.** Single-predicate `where(field => value).limit(...)` only (`lib/wild_rails_safe_introspection/adapter/filtered_lookup.rb` line 38). No `GROUP BY`, no `JOIN` paths, no aggregations exposed.
5. **No multi-framework support.** Hard dependency on `activerecord >= 7.0, < 9.0` (`wild-rails-safe-introspection-mcp.gemspec` line 20).

If you take one thing away from this section: the repo earns its narrow scope by **structural refusal**, not by hopeful policy. Every "we don't do X" claim above maps to a file you can grep. Preserve that discipline. When v2 work begins, the same standard should apply — see §8.

---

## 2. MCP Architecture + Rails Adapter

The architecture is five thin layers stacked on each other, all reachable from `lib/wild_rails_safe_introspection.rb` (the gem entry point, lines 6–29). From the agent inward:

```
MCP host (Claude Desktop / Claude Code) over stdio
  → MCP::Server (gem: mcp ~> 0.8) — JSON-RPC 2.0 transport
  → Server::ServerFactory.create — registers the 3 tools
  → Server::Tools::* — declarative MCP::Tool subclasses
  → Server::ToolHandler.execute — identity + gate + format
  → Identity::* — RequestContext, IdentityResolver, CapabilityGate
  → Guard::QueryGuard — policy enforcement (allow/deny/strip)
  → Audit::Recorder — wraps the guard block, always emits
  → Adapter::* — ActiveRecord reflection + bounded query
  → ActiveRecord::Base (host Rails app)
```

**Tool registration is static, not dynamic.** `lib/wild_rails_safe_introspection/server/server_factory.rb` lines 6–10 declares the three tools as a frozen constant `TOOLS`. The factory passes that constant straight to `MCP::Server.new` (line 13). There is no runtime tool registration API; the MCP host cannot add tools mid-session, and the allowlist YAML cannot grow the tool surface. This is Decision 7 in the safety ADRs (`000-docs/006-AT-ADEC-safety-architecture-decisions.md` lines 121–130).

**Each tool is a class inheriting `MCP::Tool`.** See for example `lib/wild_rails_safe_introspection/server/tools/inspect_model_schema.rb`. The class declares (a) `tool_name`, (b) human-readable `description`, (c) JSON-Schema `input_schema` with `required` fields, and (d) MCP-protocol `annotations` — every tool sets `read_only_hint: true, destructive_hint: false, idempotent_hint: true` (lines 21–25, mirrored in the other two tool files). Those annotations are advisory to the MCP client, not enforcement; the enforcement is downstream.

**Dispatch funnels through `Server::ToolHandler.execute`** (`lib/wild_rails_safe_introspection/server/tool_handler.rb` lines 6–15). Every tool's `call` method opens an `execute` block in identical shape:

```
ToolHandler.execute(action: '<tool_name>', resource: model_name, server_context:) do |request_context|
  Guard::QueryGuard.<method>(...)
end
```

`execute` does four things in order: (1) resolves the API key from `server_context` into a `RequestContext` via `Identity::IdentityResolver.resolve` (`identity_resolver.rb` line 8); (2) checks `Identity::CapabilityGate.permitted?` and short-circuits on denial — note that this denial is itself audited via `audit_gate_denial` (`tool_handler.rb` line 40); (3) yields the resolved context to the tool's guard call; (4) wraps the result hash as a single-text-block `MCP::Tool::Response`, setting `error: true` when the result status is `:denied` or `:error` (`tool_handler.rb` lines 32–37). The rescue at line 13 ensures the MCP host never sees an unhandled Ruby exception — internal errors are reformatted into the same response shape.

**The Rails adapter does reflection, never console.** "Adapter" here is a deliberately small surface — six modules under `lib/wild_rails_safe_introspection/adapter/`:

| Module | Job | Crucial line |
|---|---|---|
| `ModelResolver` | String name → frozen metadata hash via allowlist registry | `model_resolver.rb:7` |
| `ModelReflector` | Wrap `ModelResolver` for a `{status: :ok, model: ...}` shape | `model_reflector.rb:12` |
| `SchemaInspector` | `klass.columns` + `klass.reflect_on_all_associations` | `schema_inspector.rb:21` |
| `RecordLookup` | `klass.where(pk => id).limit(1).first` inside `Timeout.timeout` | `record_lookup.rb:30` |
| `FilteredLookup` | `klass.where(field => value).limit(max+1)` inside `Timeout.timeout` | `filtered_lookup.rb:37` |
| `ConnectionManager` | Optionally pin reads to a configured replica URL | `connection_manager.rb:7` |
| `WritePrevention` | Static refuser — name list + SQL regex | `write_prevention.rb:23–43` |

The adapter is granted **no console-equivalent surface**: there is no `klass.send(...)`, no `connection.execute(arbitrary_sql)`, no `instance_eval`. The reflection it does (`column_names`, `columns`, `reflect_on_all_associations`, `primary_key`, `table_name`) is ActiveRecord introspection on a klass that was resolved through the policy hash — never from user input. That is the "model reflection without console access" guarantee, and it is verified by both reading the code and by the adversarial spec at `spec/safety/adversarial/write_bypass_adversarial_spec.rb` lines 154–180 (dangerous-constant denial).

---

## 3. The Critical Path

A single `lookup_record_by_id` request — chosen because it touches the entire stack — flows through these calls. Method names and files are verbatim from the source.

1. **MCP transport.** The MCP host (e.g. Claude Desktop) writes a JSON-RPC `tools/call` frame to the server's stdin. `MCP::Server` (from the upstream `mcp` gem, registered in `server_factory.rb:13`) parses it, looks up the tool by name, and invokes `Tools::LookupRecordById.call(model_name:, id:, server_context:)` (`lib/wild_rails_safe_introspection/server/tools/lookup_record_by_id.rb:32`).
2. **Identity resolution.** The tool's `call` opens `ToolHandler.execute(action: 'lookup_record_by_id', resource: model_name, server_context:)`. The handler reads `server_context[:api_key]` and calls `Identity::IdentityResolver.resolve(api_key:)` (`identity_resolver.rb:8`). Empty key → `RequestContext.anonymous` (`request_context.rb:19`). Non-empty but unknown → a `:invalid` context. Match (via `ActiveSupport::SecurityUtils.secure_compare` at `identity_resolver.rb:25` — constant-time, defeats key-timing oracles) → a frozen `RequestContext` with `auth_result: :success`.
3. **Capability gate.** `ToolHandler.check_gate` calls `Identity::CapabilityGate.permitted?(request_context, action:, resource:)` (`tool_handler.rb:24`). In v1 this is a stub that returns `request_context.authenticated?` (`capability_gate.rb:41`). On denial the gate emits its own audit record via `audit_gate_denial` (`tool_handler.rb:40`) and short-circuits with a uniform `:insufficient_capability` shape.
4. **Guard layer.** The handler `yield`s to the tool's block, which calls `Guard::QueryGuard.find_by_id(model_name, id, request_context:)` (`query_guard.rb:36`). The guard immediately wraps the whole body in `Audit::Recorder.record` (`recorder.rb:6`), then performs three checks: `authenticated?` (line 40), `ColumnResolver.accessible_columns` to confirm the model is on the allowlist (line 42 — `nil` return means deny), and finally delegates to the adapter.
5. **Adapter execution.** `Adapter::RecordLookup.find_by_id` resolves the model config from `Configuration#model_config` (`record_lookup.rb:18`), then calls `execute_find` which wraps `klass.where(klass.primary_key => id).limit(1).first` inside `Timeout.timeout(timeout_s, QueryTimeoutError)` (`record_lookup.rb:30`). The `where(pk => id)` form forces parameter binding — the `id` never appears in the SQL string.
6. **Result filter.** Back in the guard, the returned `record.attributes` hash is filtered through `ResultFilter.filter_record(record, accessible_columns)` (`result_filter.rb:6`). Any blocked column is silently dropped; the response shape does not signal which columns were dropped (Decision 4, `006-AT-ADEC-...md:64`).
7. **Audit emission.** `Audit::Recorder` measures wall-clock duration via `Process::CLOCK_MONOTONIC` (`recorder.rb:7`), builds an `Audit::AuditRecord` with sanitized parameters via `ParameterSanitizer.sanitize` (`recorder.rb:28`, `parameter_sanitizer.rb:8`), and `AuditLogger.log` writes one JSON line to `configuration.audit_log_path` in append mode (`audit_logger.rb:12`). If `audit_log_path` is `nil` the line is silently dropped — that is a deliberate v1 trade-off (Decision 5).
8. **Response formatting.** `ToolHandler.format_response` (`tool_handler.rb:32`) wraps the result as a single `{type: 'text', text: JSON.generate(result)}` content block inside an `MCP::Tool::Response`, with the protocol `error` flag set when status was `:denied` or `:error`. That structure travels back over stdio to the agent.

The whole path is synchronous, single-threaded, and free of side effects beyond the JSONL append.

---

## 4. Safety Guarantees

The gem's claim is "structurally, this thing cannot write." That claim rests on four enforcement layers, three of which live in code and one of which is operator-configured infrastructure. The governing doc is `000-docs/003-TQ-STND-safety-model.md`; the architectural rationale is in `006-AT-ADEC-safety-architecture-decisions.md` Decisions 1, 2, and 3.

**Layer 1: there is no code path that calls a write method.** Read the four adapter modules that touch the DB (`record_lookup.rb`, `filtered_lookup.rb`, `schema_inspector.rb`, `model_reflector.rb`). The only ActiveRecord method calls are `where`, `limit`, `first`, `to_a`, `column_names`, `columns`, `reflect_on_all_associations`, `attributes`, `primary_key`, `table_name`, `abstract_class?`. None of these mutate. None of them invoke callbacks that could (the `touch` callback is on the forbidden list at `write_prevention.rb:14`).

**Layer 2: an active refuser sits adjacent to that path.** `Adapter::WritePrevention` (`write_prevention.rb`) exposes two assertion entry points: `assert_not_write_method!(name)` and `assert_sql_read_only!(sql)`. Both raise `WildRailsSafeIntrospection::WriteAttemptError`. The `WRITE_SQL_PATTERN` regex at line 21 covers `INSERT|UPDATE|DELETE|DROP|ALTER|TRUNCATE|CREATE|GRANT|REVOKE`, case-insensitive. Line 39 strips quoted SQL literals before pattern-matching, so values like `'Grant'` or `'%update%'` don't false-positive — verified in `spec/safety/write_prevention_safety_spec.rb` lines 51–71. *Note: nothing in the current call chain actually invokes `WritePrevention` — it is a defense-in-depth utility ready for the moment someone in the future tries to take a raw-SQL shortcut, and it is exhaustively tested as a contract.*

**Layer 3: no input can be coerced into code.** Three behaviors combine to close this:
- Model names resolve through the allowlist registry, not `constantize` (`configuration.rb:108–114` — note `safe_resolve_constant` rejects anything not matching `/\A[A-Z][A-Za-z0-9]*(::[A-Z][A-Za-z0-9]*)*\z/`).
- Filter fields are validated against `klass.column_names.include?(field)` (`filtered_lookup.rb:32` and `column_resolver.rb:19`). An unknown field gets a denial, never a method dispatch.
- Filter values and IDs are passed to `where(field => value)` and `where(pk => id)` — parameterized bindings, no string interpolation.

**Layer 4: operator-side read-only credentials and read-replica routing.** This is the only layer not in the gem. `Adapter::ConnectionManager.configure(replica_url:)` (`connection_manager.rb:15`) and the safety model Section 1 strongly recommend a read-only DB user plus a replica. When neither is configured, layers 1–3 are the entire guarantee and the safety model (line 41) says the operator should log a downgrade audit event.

The corresponding specs are at `spec/safety/write_prevention_safety_spec.rb` (52 examples covering every forbidden method name and the SQL pattern in both polarities) and the adversarial pass at `spec/safety/adversarial/write_bypass_adversarial_spec.rb` (38 examples — SQL injection through every parameter, dynamic-dispatch attempts via model names like `"Account.destroy_all"` and `"eval('exit')"`, dangerous-constant denials for `Object|Kernel|File|BasicObject|Module|Class`, null-byte injection, and a DB-state-integrity snapshot test that runs every destructive payload against all three tools and asserts the database is byte-identical afterward at lines 203–223). Per `000-docs/011-TQ-SECU-evaluation-strategy.md` line 60, the safety suite is 219 tests across 7 spec files.

---

## 5. Failure Modes & Blast Radius

The error classes are defined in `lib/wild_rails_safe_introspection.rb` lines 32–36: `ConfigError`, `ModelNotAllowedError`, `WriteAttemptError`, `QueryTimeoutError`. These are the named axes of failure; everything else collapses into `:internal_error`. The mapping of failures to outcomes:

| Failure | Where it surfaces | What the caller sees | Audit record |
|---|---|---|---|
| Unknown model | `Configuration#model_config` returns nil → guard returns `DENIAL_RESPONSE` | `{status: 'denied', reason: 'model_not_allowed'}` | `outcome: 'denied'`, `guard_result: 'denied_model_not_allowed'` |
| Unknown field on filter | `ColumnResolver.accessible_columns` includes? check fails | Same shape as unknown model | Same — by design, no separate code (Decision 4, non-enumeration) |
| Anonymous / invalid key | `RequestContext.authenticated?` false in guard | `{status: 'denied', reason: 'auth_required'}` | `caller_id: 'anonymous'` or `'unknown'` |
| Capability gate refuses | `CapabilityGate.permitted?` false at handler | `{status: 'denied', reason: 'insufficient_capability'}` | Gate emits its own audit pre-guard |
| Query times out | `Timeout.timeout` raises `QueryTimeoutError`, rescued in adapter | `{status: 'error', reason: 'query_timeout'}` | `outcome: 'timeout'` |
| ActiveRecord raises (broken model, missing table, circular reflection) | Caught by `Recorder.execute_with_rescue` (`recorder.rb:19`) | `{status: 'error', reason: 'internal_error', error_message: ...}` | `outcome: 'error'`, exception message logged |
| Truncated result set | `FilteredLookup#build_result` limits to `max_rows`, sets `truncated: true` | `{status: 'ok', truncated: true, count: N}` | `truncated: true` recorded |

**Unexpected PII in a query result.** This is the "we forgot to block `ssn`" scenario. The defense is the wildcard denylist entry (`004-TQ-STND-blocked-resource-policy.md` line 117 and the example in `012-OD-OPNS-operator-deployment-guide.md` line 120, `model: "*"` columns `ssn|credit_card_number|encrypted_password`). `ColumnResolver.accessible_columns` (`column_resolver.rb:12`) subtracts the union of model-specific and wildcard denylist entries from the model's columns. If the operator forgot to add a specific PII column, the wildcard rule still strips it — *provided* the column name was anticipated by the wildcard list. PII with an unanticipated name (e.g., `taxpayer_pin`) will leak; the residual mitigation is that every leak is auditable (Threat 3 residual-risk acknowledgement at `005-AT-ADEC-threat-model.md` line 88) and discoverable via the audit log.

**Reflection on a circular dependency.** `SchemaInspector#extract_associations` (`schema_inspector.rb:38`) iterates `klass.reflect_on_all_associations` and emits a flat list of `{name, type, target_model, foreign_key}`. It does *not* recurse into target models, so an `Order has_many :line_items, line_item belongs_to :order` cycle produces two flat reflections and stops. No stack overflow risk.

**Rails app in inconsistent state at startup.** `Configuration#load!` (`configuration.rb:26`) validates that policy files exist before attempting to resolve constants. If a model name in `allowed_models` cannot be resolved (`safe_resolve_constant` returns nil on `NameError`, line 113), it is silently dropped from the registry. **This is a sharp edge** — a typo in the YAML causes silent omission, not a loud failure. The remedy is operator vigilance plus the deployment guide's troubleshooting table (`012-...md` line 220 — but it only mentions the `NameError` shape, not silent drop). Worth a v2 fix: emit a startup warning for any allowlist entry that fails to resolve.

**Blast radius if every guarantee somehow failed simultaneously.** Read-replica routing + read-only credentials + application guard + denylist — all four would have to fail for a write to occur. In the worst plausible scenario (replica unconfigured + primary credentials are read-write + adversarial input bypassed every guard), the parameterized `where` clause still passes the value as a binding, not as SQL. A genuinely successful write would require both code-path defects *and* an ActiveRecord adapter that interprets bindings as SQL — i.e., a vulnerability in upstream Rails itself.

---

## 6. Trade-off Analysis

Decisions captured here come from `000-docs/006-AT-ADEC-safety-architecture-decisions.md` plus what is visible in the code. Each row is one ADR with the alternative path made explicit, the cost of the chosen path, and the failure mode if the choice was wrong.

| Decision | Chosen | Alternative | Why chosen | Cost paid | When it breaks |
|---|---|---|---|---|---|
| **D1: Model name → class resolution** | Allowlist hash via YAML (`configuration.rb:108`) | `model_name.constantize` (one line; standard Rails) | Closes class-resolution attack surface entirely; refuses any class not registered at boot | New model = config edit + server restart; typo'd entry silently dropped (see §5) | If `safe_resolve_constant`'s regex (`CONSTANT_NAME_PATTERN`) is ever loosened to accept arbitrary input, the safety guarantee collapses |
| **D2: DB credentials posture** | Read-only DB user *preferred*, app-level guard *always* (`003-TQ-STND-...md:32`) | Trust read-only credentials alone, or trust app guard alone | Defense-in-depth; works in dev where read-only users are awkward | Operator must remember to configure read-only creds in production for the strongest guarantee; no enforcement that they did | If both layers are misconfigured (read-write creds + a future contributor adds a write path bypassing `WritePrevention`), the gem becomes a write vector |
| **D3: Read-replica fallback** | Fall back to primary, log a warning (`006-...md:46`) | Refuse to boot without a replica | Keeps dev/test viable; primary use is operational, not analytical | If the warning is missed, an introspection query can compete with primary write workload | A noisy-neighbor incident on primary; mitigated by the row-cap + timeout but not eliminated |
| **D4: Denial response uniformity** | Same shape for "not on allowlist" and "does not exist" (`006-...md:64`) | Tell the caller exactly why | Closes the enumeration channel (Threat 3 in `005-...md`) | Agent debugging is harder — same shape for "you typo'd the model name" and "policy denies this model" | If a developer adds a specific-message path "to help debugging," the model space becomes enumerable |
| **D5: Audit storage** | JSON Lines file, append-only (`006-...md:86`, `audit_logger.rb:12`) | Database table; structured log service | Zero new infra; greppable; ships easily to log aggregators later | Not queryable in place — need `jq`/`grep`; no built-in rotation, no integrity hash chain | High-volume production deployment fills disk; rotation must be operator-configured; tampering possible by anyone with file-write access to the host |
| **D6: Filter expressivity** | Single field/value/equality only (`filtered_lookup.rb:38`) | Compound predicates, `like`, ranges | Bounded SQL surface; trivial to validate; no `OR`-based scans | Cannot ask "users active in the last 7 days"; planned for v2 (`017-PP-PLAN-v2-tool-additions.md` §2.1) | If v2's compound-predicate validator is weak, multi-predicate queries become a query-bomb vector |
| **D7: Static tool registration** | Three tools, frozen array (`server_factory.rb:8`) | One tool per allowlisted model, dynamic | Tool surface is versioned with code; changes go through PR review | Each new tool requires a release, not a config push | If a future contributor adds dynamic registration "because it's convenient," the safety boundary becomes runtime-mutable |
| **D-implicit: capability gate is a stub** | `permitted? = authenticated?` (`capability_gate.rb:41`) | Build real RBAC inline | Defer scope; v1 ships in weeks not months; `wild-capability-gate` will plug in at the same call sites | All authenticated callers have full capability; per-resource ACL is paper-only until the integration ships | If `wild-capability-gate` slips, any leaked API key gets full read access to every allowlisted model |
| **D-implicit: audit on `nil` path is silent** | `AuditLogger.log` returns early if `audit_log_path` is nil (`audit_logger.rb:10`) | Refuse to boot without a path | Allows zero-config local dev runs | An operator who forgets to set `audit_log_path` in production runs without an audit trail and the only signal is the absence of records | If the operator deployment guide (`012-...md` line 333 — "No, default nil") isn't read carefully, production silently loses §7 of the safety model |

The most consequential of these is **D-implicit: capability gate stub**. Today, any process that holds a valid API key can read every allowlisted model. The integration plan at `000-docs/016-AT-ADEC-capability-gate-integration-plan.md` is written, but until it ships, "API key valid" *is* the entire authorization model. Operators must rotate keys aggressively and scope deployment of keys per agent.

---

## 7. Operator Playbook

**Deploy alongside Rails.** This is a gem, not a service. Add to the host Rails app's `Gemfile` (`012-OD-OPNS-...md` §1), `bundle install`, then create `config/wild_introspection/access_policy.yml` and `blocked_resources.yml` using the templates in §2 and §3 of the deployment guide. Start restrictive: empty allowlist + full denylist + wildcard PII block. Add an initializer (`config/initializers/wild_introspection.rb`) that calls `WildRailsSafeIntrospection.configure` with `access_policy_path`, `blocked_resources_path`, `audit_log_path`, and `api_keys`. Generate API keys with `SecureRandom.hex(24)` (one per agent). Create `bin/wild_introspection_server` that requires `config/environment` then calls `Server::ServerFactory.create(server_context: {api_key: ENV.fetch('WILD_INTROSPECTION_API_KEY')}).run`. The server talks **stdio**, not HTTP — the MCP host launches it as a subprocess.

**Smoke-test the three tools** (`012-...md` §9):
1. *Discovery:* Connect from Claude Desktop or Claude Code via the `.mcp.json` snippet in §8 of the guide. The host should report three tools.
2. *Allowed schema:* Ask the agent to `inspect_model_schema` on a model you allowlisted. Expect column list and associations, with denylisted columns absent.
3. *Blocked-model denial:* Ask for a model you did *not* allowlist. Expect `{status: 'denied', reason: 'model_not_allowed'}` — identical shape for "blocked" and "nonexistent."
4. *Record lookup:* `lookup_record_by_id` with a valid PK. Expect `{status: 'ok', record: {...}}` with sensitive columns stripped.
5. *Filter:* `find_records_by_filter` on an allowed column. Expect `records` plus `truncated` and `count`. Try a denylisted field — expect denial.
6. *Audit verification:* `tail -5 log/wild_introspection_audit.jsonl | jq` should show one record per call including the denials.

**Roll back.** Because this is a gem loaded by Rails, rollback is `git revert` on the Gemfile and `bundle install`, then restart the MCP-server subprocess. The gem touches no Rails-app state — no migrations, no initialized data, no schema changes. The `audit.jsonl` file is the only artifact created on disk, and it is safe to keep or archive.

**Inspect audit logs.** Lines are JSON; the schema is documented at `003-TQ-STND-safety-model.md:199` and constructed at `lib/wild_rails_safe_introspection/audit/audit_record.rb:9` (`FIELDS` constant). Key queries with `jq`: denials in the last hour (`select(.outcome == "denied")`), top callers by volume (`group_by(.caller_id) | map({caller_id: .[0].caller_id, count: length})`), slow queries (`select(.duration_ms > 1000)`). Parameter values are sanitized per `parameter_sanitizer.rb` — filter values on denylisted columns are redacted, full record contents are never logged.

**Common failure modes and fixes** are tabled at `012-...md:220` and §5 above. The most operationally common is `NameError` for an allowlisted model whose class hasn't been autoloaded when the initializer runs — the fix is `Rails.application.config.after_initialize` wrapping the configure block.

---

## 8. Recommendations for v2

Honest assessment: this is the most disciplined repo of the ten in `wild-*`. The safety posture is exhaustively documented, exhaustively tested (468 examples per `021-RL-REPT-release-v0.1.0.md`), and the code matches the docs. What follows are *real* improvements, not pro-forma asks.

1. **Ship the capability gate integration.** The single largest authority gap today is that `Identity::CapabilityGate.permitted?` returns `authenticated?` — any valid API key is omnipotent within the allowlist. `000-docs/016-AT-ADEC-capability-gate-integration-plan.md` exists; until the upstream `wild-capability-gate` repo ships, this gem's authorization story is paper-only. Track that dependency explicitly.
2. **Loud failure on silently-dropped allowlist entries.** `Configuration#build_model_registry!` (`configuration.rb:85`) drops any entry whose constant fails to resolve. A typo in production silently removes a model from the agent's view. Emit a startup warning (and/or refuse to boot with a flag like `strict_allowlist: true`).
3. **Mandate an audit path.** Make `audit_log_path` required, not optional. Per Decision 5 the rationale for the JSONL backend is simplicity; the cost of "production runs without audit because someone forgot to set the path" outweighs the convenience of nil-default. If keeping nil is non-negotiable, at minimum emit a one-time stderr warning at startup when running in production-ish environments.
4. **Audit log integrity.** v1 audit records are tamper-able by anyone with file-write on the host. A hash-chain field (`prev_hash`) added to the `FIELDS` constant in `audit_record.rb` would make tampering detectable without changing the storage backend.
5. **Replica fallback should produce a startup audit event.** Decision 3 specifies the warning event; `ConnectionManager` does not currently emit one. Wire it up so the audit trail reflects the actual operating posture.
6. **Pin the upstream `mcp` gem more tightly.** The gemspec specifies `mcp ~> 0.8`. Pre-1.0 gems break compatibility frequently; consider tilde-version locking and a CI smoke test against the next minor.

Nothing above blocks production use. The v2 priorities above are listed in roughly the order of operational risk reduction per unit of work.

---

## Brief Report — Findings & Cross-Repo Issues

The repo is **production-ready against the safety model it states**. Every "we don't do X" claim is enforced by code, not by convention — the structural refusal posture is the standout property of this codebase and should set the pattern for the other nine `wild-*` repos.

Top findings (severity-ordered): (1) **Capability gate is a stub** — until `wild-capability-gate` lands, API-key validity equals omnipotence within the allowlist; this is a cross-repo dependency blocking real RBAC. (2) **Silent allowlist-entry drop** on `NameError` (`configuration.rb:91`) is a sharp edge waiting for a production typo. (3) **`audit_log_path` defaulting to `nil`** can let production run without an audit trail. (4) **No audit-log tamper resistance.** (5) **Replica-fallback warning** specified in Decision 3 is not emitted by `ConnectionManager`.

Cross-repo: this repo is one of three in the ecosystem (admin tools + capability gate + this) that share an identity/auth surface. The `RequestContext` and `CapabilityGate` shapes here will need to match the contracts in `wild-capability-gate` and `wild-admin-tools-mcp`. Worth a shared `wild-identity-contracts` doc before any of those start shipping real code.
