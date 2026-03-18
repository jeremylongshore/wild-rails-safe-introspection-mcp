# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Identity

- **Repo:** `wild-rails-safe-introspection-mcp`
- **Ecosystem:** wild (see `../CLAUDE.md` for ecosystem-level rules)
- **Mission:** Safe, governed, read-only Rails production introspection for AI agents via MCP
- **Language:** Ruby
- **Status:** v1 complete — Epics 1-9 finished, three MCP tools shipped with full safety controls

## What This Repo Does

Provides a curated set of MCP tools that let AI agents inspect live Rails application state — models, schema, records — without granting raw console access or permitting mutation. Every invocation is policy-enforced, audited, and bounded.

## What This Repo Does NOT Do

- No write operations. Read-only by design.
- No arbitrary Ruby/Rails console execution.
- No admin actions (that's `wild-admin-tools-mcp`).
- No analytics queries or reporting pipelines.
- No multi-framework support in v1 (Rails/ActiveRecord only).

## Directory Layout

```
lib/                    # Source code (Ruby convention)
  wild_rails_safe_introspection/
    adapter/            # Rails adapter layer (model reflection, safe queries)
    guard/              # Query guard / policy engine (allowlist, denylist, caps)
    audit/              # Audit trail (structured invocation logging)
    identity/           # Identity extraction and auth
    server/             # MCP server layer and tool definitions
spec/                   # Tests (RSpec)
config/                 # Configuration files (policy definitions, defaults)
000-docs/               # Canonical docs per /doc-filing
planning/               # Active planning artifacts
```

## Build Commands

```bash
bundle install          # Install dependencies
bundle exec rspec       # Run test suite
bundle exec rubocop     # Lint
```

## Testing Approach

- **RSpec** for unit and integration tests
- Tests run against a real test Rails app schema (not mocks for data access)
- Every safety claim in `003-TQ-STND-safety-model.md` must have a corresponding test
- Adversarial tests explicitly try to break safety guarantees

## Safety Rules for Claude Code

These are non-negotiable when working in this repo:

1. **Never introduce write paths.** No `save`, `create`, `update`, `destroy`, `delete`, or write SQL. If you find yourself writing code that could mutate data, stop.
2. **Never bypass the query guard.** All data access goes through the guard. No direct adapter calls from tool handlers.
3. **Never skip audit logging.** Every invocation — success, denial, error — must produce an audit record.
4. **Never expose blocked resources.** Denylist columns must be stripped before any data leaves the system.
5. **Never accept arbitrary code as input.** Tool parameters are data, not code. No `eval`, no dynamic method dispatch on user input.
6. **Prefer restrictive defaults.** When uncertain, deny access. Operators can expand later.

## Key Canonical Docs

| Doc | Purpose |
|-----|---------|
| `000-docs/001-PP-PLAN-repo-blueprint.md` | Mission, boundaries, architecture direction |
| `000-docs/002-PP-PLAN-epic-build-plan.md` | 10-epic build plan with sequencing and dependencies |
| `000-docs/003-TQ-STND-safety-model.md` | Governing safety specification — read-only enforcement, allowlist/denylist, caps, timeouts |
| `000-docs/004-TQ-STND-blocked-resource-policy.md` | Policy file format spec — allowlist YAML, denylist YAML, precedence, validation |
| `000-docs/005-AT-ADEC-threat-model.md` | 7 threats with mitigations and verification requirements |
| `000-docs/006-AT-ADEC-safety-architecture-decisions.md` | 7 safety-driven architecture decisions with rationale |
| `000-docs/008-AT-ADEC-identity-and-auth-model.md` | Identity and auth model — API key validation, RequestContext |
| `000-docs/009-AT-ADEC-capability-gate-interface.md` | Capability gate interface contract — stub for v1 |
| `000-docs/010-DR-REFF-tool-catalog.md` | v1 MCP tool catalog — schemas, safety classifications, response formats |
| `000-docs/011-TQ-SECU-evaluation-strategy.md` | Evaluation strategy — release checklist, safety defect protocol |
| `000-docs/012-OD-OPNS-operator-deployment-guide.md` | Install, configure, start, connect, verify safety controls |
| `000-docs/013-DR-REFF-configuration-reference.md` | Every parameter, type, default, hard limit |
| `000-docs/014-OD-GUID-operator-workflow-guide.md` | Add models, block columns, revoke keys, inspect audit logs |
| `000-docs/015-OD-OPNS-validation-demo.md` | Automated safety validation script and expected results |

## Task Tracking

Uses **Beads** (`bd`). All execution tracked repo-locally.

```bash
bd ready                # Find unblocked work
bd update <id> --claim  # Claim a task
bd close <id> --reason "evidence"  # Close with evidence
bd list                 # View all tasks
```

## Before Working Here

1. Read this file completely
2. Read the ecosystem CLAUDE.md at `../CLAUDE.md`
3. Check `bd ready` for current work state
4. Read the relevant canonical doc for the active epic
5. Do not skip ahead to later epics
