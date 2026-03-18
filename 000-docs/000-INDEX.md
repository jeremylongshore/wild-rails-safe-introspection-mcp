# 000-docs Index — wild-rails-safe-introspection-mcp

| # | File | Category | Type | Description |
|---|------|----------|------|-------------|
| 001 | 001-PP-PLAN-repo-blueprint.md | PP — Product & Planning | PLAN | Canonical repo blueprint — mission, vision, safety model, architecture direction |
| 002 | 002-PP-PLAN-epic-build-plan.md | PP — Product & Planning | PLAN | Canonical 10-epic build plan — sequenced execution story, child-task themes, dependencies |
| 003 | 003-TQ-STND-safety-model.md | TQ — Testing & Quality | STND | Safety model spec — read-only enforcement, allowlist/denylist, caps, timeouts, audit, defect definition |
| 004 | 004-TQ-STND-blocked-resource-policy.md | TQ — Testing & Quality | STND | Policy format spec — allowlist YAML, denylist YAML, precedence, validation, operator workflows |
| 005 | 005-AT-ADEC-threat-model.md | AT — Architecture & Technical | ADEC | Threat model — 7 threats with mitigations, residual risks, and Epic 8 verification requirements |
| 006 | 006-AT-ADEC-safety-architecture-decisions.md | AT — Architecture & Technical | ADEC | 7 safety-driven architecture decisions with context, rationale, and trade-off analysis |
| 008 | 008-AT-ADEC-identity-and-auth-model.md | AT — Architecture & Technical | ADEC | Identity and auth model — API key validation, RequestContext, anonymous rejection, constant-time comparison |
| 009 | 009-AT-ADEC-capability-gate-interface.md | AT — Architecture & Technical | ADEC | Capability gate interface contract — stub for v1, integration plan for wild-capability-gate |
| 010 | 010-DR-REFF-tool-catalog.md | DR — Documentation & Reference | REFF | v1 MCP tool catalog — tool names, schemas, safety classifications, response formats |
| 011 | 011-TQ-SECU-evaluation-strategy.md | TQ — Testing & Quality | SECU | Evaluation strategy — release checklist, safety defect protocol, test suite structure, when to re-evaluate |
| 012 | 012-OD-OPNS-operator-deployment-guide.md | OD — Operations & Deployment | OPNS | Operator deployment guide — install, configure, start, connect, verify safety controls |
| 013 | 013-DR-REFF-configuration-reference.md | DR — Documentation & Reference | REFF | Configuration reference — every parameter, type, default, hard limit, and safety warning |
| 014 | 014-OD-GUID-operator-workflow-guide.md | OD — Operations & Deployment | GUID | Operator workflow guide — add models, block columns, revoke keys, inspect audit logs |
| 015 | 015-OD-OPNS-validation-demo.md | OD — Operations & Deployment | OPNS | Deployment validation demo — automated safety check script and expected results |
| 016 | 016-AT-ADEC-capability-gate-integration-plan.md | AT — Architecture & Technical | ADEC | Capability gate integration plan — stub-to-real mapping, config, safety constraints, execution sequence |
| 017 | 017-PP-PLAN-v2-tool-additions.md | PP — Product & Planning | PLAN | Planned v2 tool additions — 3 candidates with per-tool safety checklist, threat model matrix, prerequisites |
| 018 | 018-AT-ADEC-architecture-extension-points.md | AT — Architecture & Technical | ADEC | Architecture extension points — where and how to add tools, policies, identity providers, audit backends |
| 019 | 019-AT-ADEC-telemetry-emission-hook-interface.md | AT — Architecture & Technical | ADEC | Telemetry emission hook interface — event types, privacy model, emitter/backend contracts, integration timeline |
| 020 | 020-PP-PLAN-confirmed-out-of-scope.md | PP — Product & Planning | PLAN | Confirmed out-of-scope list — permanent, version-scoped, and ecosystem boundaries with scope-change process |

## Category Reference

| Code | Meaning |
|------|---------|
| PP | Product & Planning |
| AT | Architecture & Technical |
| TQ | Testing & Quality |
| OD | Operations & Deployment |
| DR | Documentation & Reference |

## Type Reference

| Code | Meaning |
|------|---------|
| PLAN | Master plan / blueprint |
| ARCH | Architecture document |
| ADEC | Architecture decision record |
| STND | Standard / policy |
| SECU | Security evaluation / protocol |
| GUID | Workflow / operator guide |
| OPNS | Operations / deployment guide |
| REFF | Reference document |
