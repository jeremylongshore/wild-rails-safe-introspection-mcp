# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-03-18

### Added

- **MCP Server Foundation** — Full Model Context Protocol server with stdio transport
- **3 MCP Tools** — `inspect_model_schema`, `lookup_record_by_id`, `find_records_by_filter`
- **Rails Adapter Layer** — Model reflection, association inspection, safe record queries
- **Query Guard / Policy Engine** — Allowlist/denylist enforcement, row caps, query timeouts
- **Audit Trail** — Structured JSONL logging for every invocation (success, denial, error, timeout)
- **Identity & Auth** — API key validation with constant-time comparison, RequestContext
- **Capability Gate Interface** — Stub for v1, integration plan for wild-capability-gate
- **20 Canonical Docs** — Blueprint, safety model, threat model, operator guides, extension points

### Security

- Read-only enforcement at multiple layers (adapter, guard, audit)
- Adversarial test suite against 7 threat categories
- Denylist column stripping before any data leaves the system
- No `eval`, no `constantize`, no dynamic method dispatch on user input
- Query timeout and row cap hard ceilings

### Documentation

- 001: Repo blueprint — mission, vision, safety model, architecture direction
- 002: Epic build plan — 10-epic sequenced execution story
- 003: Safety model — 10 enforceable rules, defect definitions
- 004: Blocked resource policy — allowlist/denylist YAML format spec
- 005: Threat model — 7 threats with mitigations and verification requirements
- 006: Safety architecture decisions — 7 ADRs with context and rationale
- 008: Identity and auth model — API key validation, RequestContext
- 009: Capability gate interface — stub contract for v1
- 010: Tool catalog — schemas, parameters, response formats, safety classifications
- 011: Evaluation strategy — release checklist, safety defect protocol
- 012: Operator deployment guide — install, configure, start, connect, verify
- 013: Configuration reference — every parameter, type, default, hard limit
- 014: Operator workflow guide — add models, block columns, revoke keys
- 015: Validation demo — automated safety check script and expected results
- 016: Capability gate integration plan — stub-to-real mapping, execution sequence
- 017: v2 tool additions — 3 candidates with per-tool safety checklists
- 018: Architecture extension points — where to add tools, policies, providers
- 019: Telemetry emission hook interface — event types, privacy model, contracts
- 020: Confirmed out-of-scope list — permanent, version, ecosystem boundaries

[0.1.0]: https://github.com/jeremylongshore/wild-rails-safe-introspection-mcp/releases/tag/v0.1.0
