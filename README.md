# wild-rails-safe-introspection-mcp

A governed MCP server that gives AI agents read-only access to Rails application state — models, schema, and records — with policy enforcement, audit logging, and hard safety limits. No raw console access, no mutation, no arbitrary queries.

## Status

**v1 complete** — Epics 1–9 finished. Three tools shipped with full safety controls.

## Tools

| Tool | Description |
|------|-------------|
| `inspect_model_schema` | View columns, types, and associations for an allowed model |
| `lookup_record_by_id` | Fetch a single record by primary key |
| `find_records_by_filter` | Query records by a single field/value filter with row caps |

Every invocation is policy-enforced (allowlist/denylist), bounded (row caps, query timeouts), audited (structured JSONL logging), and read-only by design.

## Quick Start

See the [Operator Deployment Guide](000-docs/012-OD-OPNS-operator-deployment-guide.md) for full setup instructions.

## Documentation

| Doc | Description |
|-----|-------------|
| [Tool Catalog](000-docs/010-DR-REFF-tool-catalog.md) | Tool schemas, parameters, response formats, safety classifications |
| [Configuration Reference](000-docs/013-DR-REFF-configuration-reference.md) | Every configurable parameter with types, defaults, and hard limits |
| [Operator Workflow Guide](000-docs/014-OD-GUID-operator-workflow-guide.md) | Step-by-step workflows for common operator tasks |
| [Safety Model](000-docs/003-TQ-STND-safety-model.md) | 10 enforceable safety rules governing all server behavior |
| [Deployment Validation](000-docs/015-OD-OPNS-validation-demo.md) | Automated validation script and expected results |

## Non-Goals

- No write operations — read-only by design, enforced at multiple layers
- No arbitrary queries — only the three tools above, with fixed parameter shapes
- No multi-framework support — Rails/ActiveRecord only in v1

## Development

```bash
bundle install              # Install dependencies
bundle exec rspec           # Run test suite (468 tests)
bundle exec rubocop         # Lint
bundle exec ruby bin/validate_deployment  # Smoke test safety controls
```

## License

Intent Solutions Proprietary
