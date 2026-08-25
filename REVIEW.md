# REVIEW.md

Repository-specific law for the automated pull-request reviewer (MiniMax, two advisory lanes).

This gem is a governed MCP server that hands AI agents read-only access to a live Rails database, so
the blast radius of a defect here is production customer data. Review for safety-control regressions
first and correctness second. Report only what this pull request introduces, verified against the
surrounding source.

## What this repo is

Three MCP tools (`inspect_model_schema`, `lookup_record_by_id`, `find_records_by_filter`) exposed by
`Server::ServerFactory`. Every call travels one path and only one path:

```
Tools::* -> Server::ToolHandler -> Identity::IdentityResolver -> Identity::CapabilityGate
         -> Guard::QueryGuard (inside Audit::Recorder) -> Guard::ColumnResolver
         -> Adapter::{SchemaInspector,RecordLookup,FilteredLookup} -> Guard::ResultFilter
```

`Guard` decides. `Adapter` fetches. `Audit` records. `Identity` answers who is asking. A change that
lets any layer skip a layer to its left is the most serious class of defect in this codebase.

## Invariants (never allowed to regress)

1. **No write path.** Nothing in `lib/` may call a method in `Adapter::WritePrevention::FORBIDDEN_METHODS`
   or build SQL matching `WRITE_SQL_PATTERN`. Removing or narrowing either list is a regression, not a
   cleanup. Be precise about what enforces this today: `WritePrevention.assert_not_write_method!` and
   `assert_sql_read_only!` are assertion helpers with no call site anywhere in `lib/`, exercised only by
   `spec/safety/write_prevention_safety_spec.rb` and the unit spec. Read-only is therefore enforced by
   what the adapters actually call (`where`, `limit`, `first`, `to_a`, `attributes`) plus those specs,
   not by a runtime interceptor. A new adapter path is covered by nothing until a spec covers it.
2. **Guard is the only door.** A tool handler that reaches into `Adapter::*` directly bypasses
   `Guard::ResultFilter` and therefore returns denylisted columns. The `Adapter` modules check the
   model allowlist but they do NOT strip blocked columns. Only `Guard` does.
3. **Allowlist semantics, never denylist semantics, at the filtering step.** `ResultFilter` uses
   `select` against `accessible_columns`. Any rewrite to `reject`/`except` against a blocked list is
   fail-open: a column nobody thought to block becomes visible.
4. **`ColumnResolver.accessible_columns` returning `nil` means deny.** Callers must treat `nil` as
   `DENIAL_RESPONSE`. `QueryGuard` does this with `next DENIAL_RESPONSE unless accessible`, which catches
   `nil` only: an empty array is truthy and does reach the adapter today, contained one step later because
   `ResultFilter` then projects every row to `{}`. So a change that keeps the truthiness check but removes
   or weakens the filter step turns the empty case into a leak, and any rewrite that lets `nil` itself fall
   through is an immediate bypass.
5. **Filter fields are checked against `accessible_columns`, not against `column_names`.** Filtering on
   a blocked column is an oracle: repeated queries recover the blocked value even though the column
   is stripped from the response. `QueryGuard.find_by_filter` must keep its
   `accessible.include?(field.to_s)` check ahead of `FilteredLookup`. `FilteredLookup` has its own
   `klass.column_names` check, but that one only rejects a non-existent column, so it is defense in depth
   and never a substitute for the guard check.
6. **Every invocation, including denials and errors, emits exactly one audit record.** `Audit::Recorder`
   guarantees this from an `ensure` block for every path that reaches it, which is the guard body plus the
   capability denial that `ToolHandler.audit_gate_denial` records explicitly. It does not cover
   `ToolHandler`'s own outer `rescue StandardError`: a failure raised outside the `Recorder.record` call,
   for example in `resolve_identity`, returns an `internal_error` response with no audit record at all.
   Treat any widening of that outer rescue, an early `return` in front of `Recorder.record`, or a rescue
   that swallows the record, as blinding the operator.
7. **Tool parameters are data, never code.** User-supplied `model_name` is only ever a hash key into
   `@model_registry`. `Object.const_get` is reached only from `Configuration#safe_resolve_constant`,
   only from an operator-authored policy file, and only behind `CONSTANT_NAME_PATTERN`. Routing tool
   input to `const_get`, `send`, `public_send`, `eval`, or `constantize` is a top-severity finding.
8. **Queries stay parameterized.** `klass.where(field => value)` with `field` pre-validated. Any string
   interpolation into `where`, `order`, `select`, `pluck`, or `execute` is SQL injection here, because
   `value` arrives straight from an untrusted agent.
9. **Caps are ceilings, not defaults.** `HARD_ROW_CEILING` (1000) and `HARD_TIMEOUT_CEILING_MS` (30000)
   are enforced with `clamp` in `Configuration` and again with `min` in `FilteredLookup`. `HARD_ROW_CEILING`
   is declared twice, once per module, so a change that raises one and not the other leaves a silent
   disagreement between config time and query time. Replacing either with `||` or a config-supplied value lets an
   operator (or a bad policy file) uncap production. `limit(max_rows + 1)` is the truncation detector:
   dropping the `+ 1` silently reports `truncated: false` on a truncated result.
10. **Denials do not leak existence.** `model_not_allowed` is the answer for both "no such model" and
    "blocked model". Do not let a new error message distinguish the two.

## Top defect classes to hunt, in order

1. **Fail-open capability gate.** `Identity::CapabilityGate.permitted?` is a documented v1 stub that
   returns `request_context.authenticated?`. Its stub-ness is intentional (see `000-docs/009`), so do
   not report that. DO report any change that makes it return true for an unauthenticated or
   `:invalid` context, rescues an exception into a permit, defaults `resource` in a way that skips a
   check, or moves the call site below the data fetch.
2. **Authentication bypass.** `IdentityResolver` must keep `ActiveSupport::SecurityUtils.secure_compare`
   (a `==` on an API key is a timing oracle) and must keep mapping nil, empty, and unmatched keys to a
   non-authenticated context. `RequestContext` is frozen on construction: a mutable context is a
   privilege-escalation surface.
3. **Data leak through the response.** Anything that widens what leaves the process: schema columns not
   passed through `filter_schema_columns`, `record.attributes` returned unfiltered, association
   metadata exposing a blocked column via `foreign_key`, or a new response field carrying raw model state.
4. **PII escaping the audit log.** `Audit::ParameterSanitizer.sanitize` returns `nil` for any tool name
   it does not know, so a fourth tool added without a matching `case` branch logs unsanitized
   parameters. Only `find_records_by_filter` values are redacted, and only when the field itself is
   blocked. Also watch `error_message`, which propagates a raw exception message (potentially a row of
   data or a connection string) into the audit record and into the MCP response.
5. **Unbounded work.** A new query path without `Timeout.timeout`, without a row cap, or one that
   materializes with `to_a`/`map` before limiting, is a denial-of-service against the host application
   database.
6. **Connection scope.** `Adapter::ConnectionManager#establish_replica` calls
   `ActiveRecord::Base.establish_connection`, which re-points the whole host application, not just this
   gem. Scrutinize any change here for effects on the embedding app, and for a replica URL reaching a
   log or an error message.
7. **Config parsing.** `YAML.safe_load_file` only. `YAML.load`, `unsafe_load`, `aliases: true`, or ERB
   in a policy file turns operator config into code execution. Policy data is frozen after `load!` so
   the allowlist cannot drift at runtime: keep it that way.
8. **Ordinary correctness.** Real bugs in Ruby control flow, `ensure` blocks that mask the return value,
   symbol/string key mismatches between `Guard` and `Adapter` (`accessible_columns` compares `to_s`,
   attributes come back as strings, schema columns as symbol-keyed hashes), and workflow errors.

## What "fail closed" means here

On any uncertainty the answer is a denial with a generic reason, plus an audit record. Concretely:
unknown model denies, unknown or blocked filter field denies, unauthenticated denies before any
adapter call runs, a timeout returns an error and never a partial row set, a rescued exception returns
`internal_error` rather than a result, and a missing or unreadable policy file raises `ConfigError` at
boot rather than starting with an empty (permissive-looking) registry. If a change makes any of these
paths return data, succeed silently, or default to permitted, say so plainly and rank it first.

## Tests are part of the safety argument

`spec/safety/` and `spec/safety/adversarial/` exist to prove the invariants above, not to pad coverage.
A pull request that changes a guard, the gate, the sanitizer, or a cap without touching those specs is
incomplete. Deleting, skipping, or loosening an adversarial expectation to make a change pass is a
finding in its own right, and outranks whatever the change was.

## Files not to hand-edit

`Gemfile.lock` (regenerate with `bundle`), and the numbered `000-docs/NNN-CC-ABCD-*.md` set, which
follows a filing convention: new docs take the next number, existing ones are corrected in place with
a dated note rather than renumbered. `.beads/` is untracked.

## Do not waste comments on

RuboCop and RSpec findings (CI runs both and is the gate), the existing `# rubocop:disable Metrics/*`
annotations, `frozen_string_literal` headers, that `CapabilityGate` is a stub, that only three tools
exist, that v2 tools are missing (`000-docs/017` and `000-docs/020` scope that deliberately),
Ruby style preferences, docstring wording, or the proprietary license header. No praise-only comments.

## Anti-ratchet

On a re-review after new pushes the bar does not rise. Drop findings the update resolved and do not
invent objections on unchanged lines you already accepted. Prefer a few high-conviction findings over
a long list. If the change is safe, correct, and covered, reply `lgtm`. This reviewer is advisory only
and never blocks a merge.

## Sources

Every code-grounded claim above was verified by reading the file at the commit this pull request branch
points at, short SHA `0d942cb`. Line numbers are that commit's. Three claims were wrong when first written
and have been corrected in place: INV-1 (the `WritePrevention` lists have no runtime call site), INV-4
(an empty `accessible_columns` array is truthy and does reach the adapter), and INV-6 (the `ensure`
guarantee does not cover `ToolHandler`'s outer rescue). Paths below are relative to `lib/` unless the entry
says otherwise.

### Architecture

- Three tools, registered: `lib/wild_rails_safe_introspection/server/server_factory.rb:6-10`
- Call path, tool entry: `server/tools/find_records_by_filter.rb:36-46` (same shape in
  `server/tools/inspect_model_schema.rb:28-36` and `server/tools/lookup_record_by_id.rb:28-40`)
- Call path, identity then gate then guard: `server/tool_handler.rb:6-15`
- Call path, guard then resolver then adapter then filter: `guard/query_guard.rb:58-71`

### Invariants

- INV-1 lists: `adapter/write_prevention.rb:6-21`; assertion helpers `:23-43`; no call site in `lib/`
  (verified by grep across `lib/`); spec call sites `spec/safety/write_prevention_safety_spec.rb:13,45,67`
  and `spec/wild_rails_safe_introspection/adapter/write_prevention_spec.rb:26-65`
- INV-2 adapters check the allowlist only: `adapter/record_lookup.rb:18-19,34`,
  `adapter/filtered_lookup.rb:15-16,49`, `adapter/schema_inspector.rb:13-14,26-36`; stripping happens in
  `guard/result_filter.rb:6-16` alone
- INV-3 allowlist semantics via `select`: `guard/result_filter.rb:7,11,15`
- INV-4 `nil` return: `guard/column_resolver.rb:9`; callers denying on it: `guard/query_guard.rb:25,44,62`;
  the filter step that contains the empty case: `guard/query_guard.rb:31,49,69`
- INV-5 guard-level field check ahead of the adapter: `guard/query_guard.rb:63` before `:65`; the adapter's
  own existence check: `adapter/filtered_lookup.rb:21,31-33`
- INV-6 `ensure` block: `audit/recorder.rb:9-16`; rescue into `internal_error`: `audit/recorder.rb:18-22`;
  capability denial recorded explicitly: `server/tool_handler.rb:40-47`; the uncovered outer rescue:
  `server/tool_handler.rb:13-14`
- INV-7 `model_name` used only as a registry key: `configuration.rb:35-45`; the single `Object.const_get`:
  `configuration.rb:108-113`, reached only from `configuration.rb:90` with a name read from the operator
  policy file; `CONSTANT_NAME_PATTERN`: `configuration.rb:7`. No `eval`, `constantize`, or `send` on tool
  input anywhere in `lib/` (the one `public_send` is over a fixed field list, `audit/audit_record.rb:53`)
- INV-8 parameterized queries: `adapter/filtered_lookup.rb:38`, `adapter/record_lookup.rb:31`; no string
  interpolation into any query method in `lib/` (verified by grep)
- INV-9 ceilings: `configuration.rb:8-9`; `clamp` at `configuration.rb:80-81,103-104`; `min` at
  `adapter/filtered_lookup.rb:23`; duplicate constant at `adapter/filtered_lookup.rb:6`; truncation
  detector `limit(max_rows + 1)` at `adapter/filtered_lookup.rb:38` with the comparison at `:46-47`
- INV-10 one reason for both cases: `guard/query_guard.rb:6-10`; blocked models are dropped from the
  registry, which is what makes them indistinguishable from unknown ones, `configuration.rb:88`

### Defect classes

- Capability gate stub returning `request_context.authenticated?`: `identity/capability_gate.rb:37-42`,
  documented as a v1 stub at `:9-17` and in `000-docs/009-AT-ADEC-capability-gate-interface.md`
- `secure_compare` on the API key: `identity/identity_resolver.rb:25`; nil or empty maps to anonymous
  `:9`; unmatched maps to `:invalid` `:12-16`; `RequestContext` frozen on construction:
  `identity/request_context.rb:12`
- Schema columns filtered but associations not: `guard/query_guard.rb:30-32` filters only `:columns`,
  while `adapter/schema_inspector.rb:38-47` emits `foreign_key` per association
- `record.attributes` leaving the adapter unfiltered: `adapter/record_lookup.rb:34`,
  `adapter/filtered_lookup.rb:49`
- `ParameterSanitizer.sanitize` returning `nil` for an unknown tool name (a `case` with no `else`):
  `audit/parameter_sanitizer.rb:8-17`; redaction only for `find_records_by_filter` and only for a blocked
  field: `audit/parameter_sanitizer.rb:19-25`; `error_message` carrying a raw exception message into the
  audit record and into the response: `audit/recorder.rb:21,32` and `server/tool_handler.rb:14`
- Timeouts and row caps: `adapter/record_lookup.rb:28-32`, `adapter/filtered_lookup.rb:24,37-39`
- `establish_replica` re-pointing the host app: `adapter/connection_manager.rb:35-38`
- `YAML.safe_load_file` only: `configuration.rb:64,72`; policy data frozen after `load!`:
  `configuration.rb:75-76,128-132`
- Symbol versus string keys: `guard/result_filter.rb:7` compares `key.to_s` against string column names,
  while schema columns are symbol-keyed hashes, `adapter/schema_inspector.rb:28-34`

### Fail closed

- Unknown model denies: `guard/query_guard.rb:25,44,62`
- Unknown or blocked filter field denies: `guard/query_guard.rb:63`, `adapter/filtered_lookup.rb:21`
- Unauthenticated denies before any adapter call: `guard/query_guard.rb:22,40,59`, plus the gate at
  `server/tool_handler.rb:8-9`
- Timeout returns an error, never a partial row set: `adapter/record_lookup.rb:22-23`,
  `adapter/filtered_lookup.rb:27-28`
- Rescued exception returns `internal_error`: `audit/recorder.rb:20-21`
- Missing or unreadable policy file raises `ConfigError` at boot: `configuration.rb:54-61,65,73`

### Tests, files, and CI

- Safety suites exist: `spec/safety/` (3 specs) and `spec/safety/adversarial/` (4 specs)
- `Gemfile.lock` is committed; `000-docs/` holds the numbered set (`000-INDEX.md` plus `001` through `022`)
- `.beads/` is untracked: `.gitignore:6`
- The deterministic gate is rspec plus rubocop: `.github/workflows/ci.yml:21-25`
- Existing `rubocop:disable Metrics/*` annotations: `guard/query_guard.rb:18,36,54`,
  `audit/recorder.rb:37`, `configuration.rb:6`
- v2 tools deliberately out of scope: `000-docs/017-PP-PLAN-v2-tool-additions.md`,
  `000-docs/020-PP-PLAN-confirmed-out-of-scope.md`
- Proprietary license: `LICENSE:1`, `README.md:54`

### Claims made in the workflow file

- `read_only_hint` is annotation metadata, not enforcement: `server/tools/find_records_by_filter.rb:29-33`
  (same block in the other two tools)
- "Activation: ALREADY SET" checked against the repository settings: variables `ENABLE_MINIMAX_REVIEW=true`
  and `MINIMAX_MODEL=MiniMax-M3`, secret `MINIMAX_API_KEY` present, read back with
  `gh api repos/jeremylongshore/wild-rails-safe-introspection-mcp/actions/variables` and `.../secrets`
- "The action fetches the PR diff via the API and never checks out or executes PR code" checked at the
  pinned SHA `d1314b9` of `jeremylongshore/minimax-code-review`: `action.yml:35-37` runs a node20 entry
  point with no checkout step, and `src/index.js:54,77` builds the review input from
  `octokit.rest.pulls.listFiles` patches. The shipped bundle is `dist/index.js`, built from that source,
  so this verifies the source at the pin and not the bundle byte for byte.
