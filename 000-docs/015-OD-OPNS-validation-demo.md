# 015 — Deployment Validation Demo

**Category:** OD — Operations & Deployment
**Type:** OPNS — Operations guide
**Status:** v1

Documents the `bin/validate_deployment` script — what it checks, how to run it, and how to interpret results.

---

## Purpose

The validation script provides a quick, automated way to verify that the MCP server's safety controls are working correctly. It configures the server with test fixtures, seeds sample data, invokes all three tools, and checks that safety guarantees hold.

Run it after deployment, after configuration changes, or as a smoke test in CI.

---

## Running the Script

```bash
ruby bin/validate_deployment
```

**Requirements:**
- Ruby (same version as the project)
- `bundle install` completed (needs `sqlite3`, `activerecord`, and project gems)

**Exit codes:**
- `0` — All checks passed
- `1` — One or more checks failed

---

## What It Checks

The script runs 7 checks covering the core safety guarantees:

| # | Check | Safety Claim Verified |
|---|-------|-----------------------|
| 1 | Schema inspection returns columns for an allowed model | Allowlist grants access |
| 2 | Blocked columns are absent from schema results | Denylist strips sensitive columns |
| 3 | Record lookup returns data with blocked columns stripped | Denylist enforcement on record data |
| 4 | Filter query returns correct matching records | Query execution and result filtering |
| 5 | Truncation flag is false when under row cap | Row cap and truncation flag accuracy |
| 6 | Blocked model (CreditCard) is denied | Blocked model list overrides allowlist |
| 7 | Anonymous request is rejected | Authentication enforcement |

---

## Expected Output

```
wild-rails-safe-introspection deployment validation
=======================================================

  ✓ PASS: Schema inspection returns columns for allowed model
  ✓ PASS: Blocked columns absent from schema (checked: stripe_customer_id, tax_id, ssn)
  ✓ PASS: Record lookup returns data with blocked columns stripped
  ✓ PASS: Filter query returns matching records (2 active users)
  ✓ PASS: Truncation flag is false when under row cap
  ✓ PASS: Blocked model (CreditCard) is denied
  ✓ PASS: Anonymous request is rejected

7 passed, 0 failed
```

---

## Interpreting Failures

| Failed Check | Likely Cause |
|--------------|--------------|
| Schema inspection | Model not in `access_policy.yml`, or class not loadable |
| Blocked columns present | `blocked_resources.yml` missing entries, or column exposure mode set to `all` |
| Record lookup | Database not seeded, or column filtering broken |
| Filter query | Query guard or filtered lookup not wired correctly |
| Truncation flag wrong | Row cap logic or truncation detection issue |
| Blocked model allowed | Model not in `blocked_models` list, or blocked list not loaded |
| Anonymous allowed | Authentication bypass — identity resolver not rejecting nil keys |

Any failure indicates a safety control is not working as expected. Investigate before deploying.

---

## How It Works

1. Sets up an in-memory SQLite database with the test schema (same schema used by the test suite)
2. Configures `WildRailsSafeIntrospection` with the test fixture policy files (`spec/fixtures/access_policy.yml` and `spec/fixtures/blocked_resources.yml`)
3. Seeds sample data: 1 account, 3 users (2 active, 1 inactive)
4. Invokes tools via `QueryGuard` directly (bypasses MCP transport, tests the safety logic)
5. Asserts expected outcomes for each check
6. Reports pass/fail for each check and exits with appropriate code

The script reuses the project's existing test fixtures rather than duplicating configuration, ensuring the validation matches what the test suite verifies.
