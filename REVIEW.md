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
   cleanup.
2. **Guard is the only door.** A tool handler that reaches into `Adapter::*` directly bypasses
   `Guard::ResultFilter` and therefore returns denylisted columns. The `Adapter` modules check the
   model allowlist but they do NOT strip blocked columns. Only `Guard` does.
3. **Allowlist semantics, never denylist semantics, at the filtering step.** `ResultFilter` uses
   `select` against `accessible_columns`. Any rewrite to `reject`/`except` against a blocked list is
   fail-open: a column nobody thought to block becomes visible.
4. **`ColumnResolver.accessible_columns` returning `nil` means deny.** Callers must treat `nil` as
   `DENIAL_RESPONSE`. A truthiness check that lets `nil` or `[]` fall through to the adapter is a bypass.
5. **Filter fields are checked against `accessible_columns`, not against `column_names`.** Filtering on
   a blocked column is an oracle: repeated queries recover the blocked value even though the column
   is stripped from the response. `QueryGuard.find_by_filter` must keep its
   `accessible.include?(field.to_s)` check ahead of `FilteredLookup`.
6. **Every invocation, including denials and errors, emits exactly one audit record.** `Audit::Recorder`
   guarantees this from an `ensure` block. Adding an early `return` in front of `Recorder.record`, or a
   rescue that swallows the record, silently blinds the operator.
7. **Tool parameters are data, never code.** User-supplied `model_name` is only ever a hash key into
   `@model_registry`. `Object.const_get` is reached only from `Configuration#safe_resolve_constant`,
   only from an operator-authored policy file, and only behind `CONSTANT_NAME_PATTERN`. Routing tool
   input to `const_get`, `send`, `public_send`, `eval`, or `constantize` is a top-severity finding.
8. **Queries stay parameterized.** `klass.where(field => value)` with `field` pre-validated. Any string
   interpolation into `where`, `order`, `select`, `pluck`, or `execute` is SQL injection here, because
   `value` arrives straight from an untrusted agent.
9. **Caps are ceilings, not defaults.** `HARD_ROW_CEILING` (1000) and `HARD_TIMEOUT_CEILING_MS` (30000)
   are enforced with `clamp` and `min`. Replacing either with `||` or a config-supplied value lets an
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
