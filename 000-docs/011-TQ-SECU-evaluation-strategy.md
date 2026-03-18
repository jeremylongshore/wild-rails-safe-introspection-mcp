# Evaluation Strategy — wild-rails-safe-introspection-mcp

**Document type:** Security evaluation protocol
**Filed as:** `011-TQ-SECU-evaluation-strategy.md`
**Status:** Active — governing evaluation protocol for all releases
**Last updated:** 2026-03-18
**Epic:** 8 — Prove the Safety Model Holds

---

## Purpose

This document defines the protocol for proving that `wild-rails-safe-introspection-mcp` meets its safety guarantees before every release, every new Rails app connection, and every new tool addition. It is written for a capable engineer who has not read the codebase.

If you are deploying this server, adding a tool, or cutting a release, follow this document.

---

## What This Server Guarantees

The server promises five safety properties (defined in `003-TQ-STND-safety-model.md`):

1. **Read-only enforcement** — no code path can write, update, or delete data
2. **Allowlist-based model access** — only explicitly allowed models are accessible
3. **Denylist column stripping** — blocked columns never appear in any response
4. **Resource limits** — row caps and query timeouts are enforced and cannot be bypassed
5. **Input treated as data** — tool parameters are never executed as code or SQL

A failure of any of these properties is a **safety defect** that blocks release.

---

## What Is Tested

The test suite is organized in two layers:

### Layer 1: Structural Safety Tests (103 tests)

These verify that each component enforces its contract under normal and edge-case conditions.

| File | Tests | Coverage |
|------|-------|----------|
| `spec/safety/write_prevention_safety_spec.rb` | 52 | Every adapter method refuses writes; no write-capable ActiveRecord methods exist in the call chain |
| `spec/safety/server_edge_safety_spec.rb` | 27 | Tool set immutability, audit completeness, gate denial uniformity, response format consistency, blocked column stripping |
| `spec/safety/server_integration_spec.rb` | 24 | End-to-end MCP tool invocations: authentication, schema inspection, record lookup, filtered search, audit trail |

### Layer 2: Adversarial Safety Tests (116 tests)

These attempt to break the safety guarantees using attack vectors from the threat model (`005-AT-ADEC-threat-model.md`).

| File | Tests | Coverage |
|------|-------|----------|
| `spec/safety/adversarial/write_bypass_adversarial_spec.rb` | 38 | SQL injection via all parameters, dynamic dispatch prevention, code execution via model_name, DB state integrity after destructive payloads, prompt injection (SQL fragments, control characters, AR method names) |
| `spec/safety/adversarial/access_control_adversarial_spec.rb` | 41 | Case variation bypass, encoding/namespace tricks, table name bypass, SQL fragments in model_name, model enumeration resistance, timing consistency, table-prefixed columns, SQL aliases in field, schema/data consistency for blocked columns, column enumeration resistance, configuration immutability |
| `spec/safety/adversarial/resource_limits_adversarial_spec.rb` | 20 | SQL bypass of row caps/timeouts, precise boundary enforcement (100 vs 101 records), sequential cap independence, timeout zero-partial-results, timeout wrapper verification |
| `spec/safety/adversarial/audit_integrity_adversarial_spec.rb` | 17 | Audit record completeness, identity attribution, parameter sanitization, exception-path auditing |

### Total Safety Coverage

- **219 safety-focused tests** across 7 spec files
- **468 tests** in the full suite (including unit and integration tests for all components)
- **0 rubocop offenses** enforced by CI

---

## How to Run the Tests

### Prerequisites

- Ruby (version specified in `.ruby-version` or Gemfile)
- Bundler (`gem install bundler`)
- All dependencies installed (`bundle install`)
- No external services required — tests use an in-memory SQLite database

### Commands

Run the full test suite:

```bash
bundle exec rspec
```

Run only safety tests (structural + adversarial):

```bash
bundle exec rspec spec/safety/
```

Run only adversarial tests:

```bash
bundle exec rspec spec/safety/adversarial/
```

Run tests with documentation output (useful for auditing what is covered):

```bash
bundle exec rspec spec/safety/ --format documentation
```

Run linting:

```bash
bundle exec rubocop
```

### Expected Output

A passing run looks like:

```
468 examples, 0 failures
```

Any output other than `0 failures` is a blocking issue.

---

## What Constitutes a Passing Result

All of the following must be true:

1. `bundle exec rspec` — **0 failures** across the full suite
2. `bundle exec rspec spec/safety/` — **0 failures** across all safety tests
3. `bundle exec rubocop` — **0 offenses**
4. No test is skipped or pending without a documented reason in the test file
5. CI pipeline passes (the `test` job in GitHub Actions must be green)

---

## What Constitutes a Safety Defect

Any of the following is a safety defect:

1. **Any adversarial test fails** — an attack vector succeeded
2. **A write path is discovered** — any code path that could mutate data (even theoretically)
3. **A blocked column appears in a response** — denylist stripping was bypassed
4. **A blocked or non-allowlisted model is accessible** — allowlist enforcement was bypassed
5. **Row cap or timeout can be bypassed** — resource limits are not enforced
6. **User input is executed as code or SQL** — parameters are not treated as data
7. **An invocation produces no audit record** — audit trail has a gap
8. **Denial responses leak information** — blocked vs. non-existent resources produce different responses

---

## How to Handle a Safety Defect

1. **Stop the release.** Do not ship the current version.
2. **Create a bead** for the defect with label `safety-defect` and priority P1.
3. **Write a failing test** that demonstrates the defect before writing any fix.
4. **Fix the defect** in the production code.
5. **Verify the fix** — the new test passes, all existing tests still pass.
6. **Run the full evaluation** — all commands in the "How to Run the Tests" section.
7. **Document the defect** in the PR description: what failed, why, and what was fixed.
8. **Get the PR reviewed** before merging.

Never suppress a failing safety test. Never mark a safety test as pending to unblock a release.

---

## Release Checklist

Use this checklist before every release. Every item must be checked.

### Pre-release verification

- [ ] `bundle exec rspec` passes with 0 failures
- [ ] `bundle exec rspec spec/safety/` passes with 0 failures
- [ ] `bundle exec rspec spec/safety/adversarial/` passes with 0 failures
- [ ] `bundle exec rubocop` passes with 0 offenses
- [ ] CI pipeline is green on the release branch
- [ ] No tests are skipped or pending without documented reason
- [ ] No new write-capable methods (`save`, `create`, `update`, `destroy`, `delete`, `eval`, `send` with user input) appear in production code

### If a new tool was added

- [ ] Tool delegates through `ToolHandler.execute` (not direct adapter calls)
- [ ] Tool produces an audit record for every outcome (success, denial, error, timeout)
- [ ] Tool respects allowlist — denied models return the standard denial response
- [ ] Tool respects denylist — blocked columns are stripped from all responses
- [ ] Tool respects row caps and timeouts
- [ ] Tool does not execute user parameters as code or SQL
- [ ] New adversarial tests cover the tool's specific attack surface
- [ ] Denial responses for the new tool are indistinguishable from existing denials

### If a new Rails app is connected

- [ ] The access policy YAML (`access_policy.yml`) lists only the models intended for access
- [ ] The blocked resources YAML (`blocked_resources.yml`) blocks all sensitive columns
- [ ] Database credentials are read-only (or the downgrade is logged per the safety model)
- [ ] Run the full test suite against the new configuration
- [ ] Verify that blocked columns from the new app's schema do not appear in any response

### If the access policy was modified

- [ ] New allowed models have appropriate `max_rows` and `query_timeout_ms` settings
- [ ] New allowed models do not expose sensitive columns — check `blocked_resources.yml`
- [ ] Removed models are no longer accessible (test with a manual tool invocation)
- [ ] `bundle exec rspec spec/safety/` still passes

### Final sign-off

- [ ] All checklist items above are complete
- [ ] The release PR is approved
- [ ] No open safety-defect beads exist

---

## When to Run This Evaluation

| Event | Scope |
|-------|-------|
| Every PR | Full test suite via CI |
| Every release | Full checklist above |
| New tool added | Full checklist + new-tool section |
| New Rails app connected | Full checklist + new-app section |
| Access policy change | Full checklist + policy-change section |
| Safety defect reported | Defect handling procedure above |

---

## Reference Documents

| Document | Purpose |
|----------|---------|
| `003-TQ-STND-safety-model.md` | The governing safety specification — defines the rules these tests enforce |
| `004-TQ-STND-blocked-resource-policy.md` | Policy file format — how allowlists and denylists are configured |
| `005-AT-ADEC-threat-model.md` | 7 threats with mitigations — the adversarial tests are derived from these |
| `006-AT-ADEC-safety-architecture-decisions.md` | Architecture decisions that shape the safety implementation |
| `010-DR-REFF-tool-catalog.md` | v1 tool definitions — what each tool does and its safety classification |
