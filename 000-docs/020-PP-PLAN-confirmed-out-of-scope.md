# Confirmed Out-of-Scope List — wild-rails-safe-introspection-mcp

**Document type:** Planning
**Filed as:** `020-PP-PLAN-confirmed-out-of-scope.md`
**Status:** Active — canonical out-of-scope reference
**Last updated:** 2026-03-18
**Epic:** 10 — Expansion Readiness
**Task:** 1cv.5 — Write and file the confirmed out-of-scope list

---

## Purpose

This document is the single canonical reference for what this repo will not do. It consolidates out-of-scope decisions currently scattered across the blueprint ([001](001-PP-PLAN-repo-blueprint.md)), v2 tool additions plan ([017](017-PP-PLAN-v2-tool-additions.md)), and [CLAUDE.md](../CLAUDE.md) into one authoritative list.

Future sessions should check this document before proposing new features. If something is listed here, it requires the scope-change process in Section 5 — not silent re-litigation.

---

## 1. Permanent Boundaries

These are design invariants. They will never be in scope for this repo regardless of version. Violating any of these would fundamentally contradict the repo mission.

**Write operations.** No create, update, delete, or mutation of any kind. The read-only constraint is a design invariant, not a version-gated feature. Write capability belongs in `wild-admin-tools-mcp`.
*Sources: [001 §5](001-PP-PLAN-repo-blueprint.md), [017 §5](017-PP-PLAN-v2-tool-additions.md), [CLAUDE.md](../CLAUDE.md)*

**Arbitrary Ruby/Rails execution.** No tool that accepts Ruby code as input. No `eval`, no console emulation, no dynamic method dispatch on user input. Tool parameters are data, never code.
*Sources: [001 §5](001-PP-PLAN-repo-blueprint.md), [017 §5](017-PP-PLAN-v2-tool-additions.md), [CLAUDE.md](../CLAUDE.md)*

**Admin operations.** Running jobs, clearing caches, updating feature flags, managing users — all belong in `wild-admin-tools-mcp`. This repo reads; that repo acts.
*Sources: [001 §5](001-PP-PLAN-repo-blueprint.md), [017 §5](017-PP-PLAN-v2-tool-additions.md), [CLAUDE.md](../CLAUDE.md)*

**Dynamic tool registration at runtime.** The tool set is fixed at startup via `ServerFactory::TOOLS` (a frozen array). No MCP client can register, modify, or remove tools during a session.
*Sources: [017 §5](017-PP-PLAN-v2-tool-additions.md)*

**Arbitrary SQL execution.** Tool parameters are data, not code. No raw SQL fragments, no SQL interpolation, no user-provided query strings. All queries are constructed programmatically through the adapter layer.
*Sources: [003](003-TQ-STND-safety-model.md), [005](005-AT-ADEC-threat-model.md)*

---

## 2. Version-Scoped Boundaries

These are not in v1 (or v2 where noted). Some may evolve in later versions with proper safety review. Each item notes the version boundary and what would be required to reconsider.

**Analytics and aggregation queries.** GROUP BY, window functions, cross-model joins for reporting. The tools answer operational questions ("what is this record?"), not business intelligence questions ("how many users signed up last week?"). Reconsidering would require a new tool category with its own threat model.
*Sources: [001 §5](001-PP-PLAN-repo-blueprint.md), [017 §5](017-PP-PLAN-v2-tool-additions.md), [CLAUDE.md](../CLAUDE.md)*

**Multi-framework support.** Rails/ActiveRecord only in v1. Support for Hanami, Sinatra with Sequel, etc. is a future extension. Reconsidering would require adapter abstraction and per-framework safety validation.
*Sources: [001 §5](001-PP-PLAN-repo-blueprint.md), [CLAUDE.md](../CLAUDE.md)*

**Multi-hop association traversal.** v2 supports one hop only. Multi-hop traversal dramatically increases the attack surface for data exfiltration and query abuse. Reconsidering would require its own threat model review, traversal depth limits, visited-set tracking, and aggregate row caps across hops.
*Sources: [017 §5](017-PP-PLAN-v2-tool-additions.md)*

**`has_many :through` associations.** Excluded even from v2 single-hop traversal because it implies an intermediate join table that may not be allowlisted. Supporting it safely requires validating all three models (source, through, target).
*Sources: [017 §5](017-PP-PLAN-v2-tool-additions.md)*

**Streaming and pagination.** Results beyond the row cap are truncated. Cursor-based pagination would require stateful session management and introduces new attack vectors (cursor manipulation, session fixation).
*Sources: [017 §5](017-PP-PLAN-v2-tool-additions.md)*

**Compound predicates beyond v2 spec.** v2 allows one level of AND/OR with a predicate cap. Nested predicate groups, subqueries, and recursive filter structures are out of scope.
*Sources: [017 §2.1](017-PP-PLAN-v2-tool-additions.md)*

**Compliance dashboard product.** Audit logs are for operational accountability, not for satisfying formal compliance frameworks (SOC2, HIPAA, etc.). Those requirements may inform the design but the repo is not a compliance product.
*Sources: [001 §5](001-PP-PLAN-repo-blueprint.md)*

---

## 3. Ecosystem Boundaries

These capabilities belong in other `wild-*` repos. They are out of scope here not because they are unimportant, but because they have different safety models, different users, or different operational profiles.

| Capability | Belongs in | Why not here |
|-----------|-----------|-------------|
| Write/admin operations | `wild-admin-tools-mcp` | Different safety model (mutation vs read-only) |
| Telemetry aggregation and dashboards | `wild-session-telemetry` | Different data lifecycle and privacy model |
| Gap analysis from usage data | `wild-gap-miner` | Analytics workload, not operational introspection |
| Transcript processing | `wild-transcript-pipeline` | ETL pipeline, not real-time tool serving |
| Skill/capability registry | `wild-skillops-registry` | Control plane, not data plane |

This repo emits telemetry events via the hook interface ([019](019-AT-ADEC-telemetry-emission-hook-interface.md)) and integrates with the capability gate ([016](016-AT-ADEC-capability-gate-integration-plan.md)), but it does not own those systems.

---

## 4. Why These Boundaries Exist

Every boundary above traces back to one or more of these principles:

**Safety model integrity.** The read-only, policy-enforced, audited design is the repo's core value proposition. Features that weaken this — writes, arbitrary execution, unbounded queries — destroy the trust model that makes the tool useful in the first place. See [003 — Safety Model](003-TQ-STND-safety-model.md).

**Attack surface control.** Each new capability adds threat surface. The threat model ([005](005-AT-ADEC-threat-model.md)) evaluates 7 threat categories per tool. Features with high threat amplification (multi-hop traversal, nested predicates, raw SQL) require disproportionate safety investment relative to their operational value.

**Repo focus.** The `wild` ecosystem is designed as composable repos with clear boundaries ([../CLAUDE.md](../CLAUDE.md)). Capabilities that serve different users, have different safety profiles, or require different operational infrastructure belong in their own repo.

**Ship-useful-things pragmatism.** Scope creep delays useful deliverables. A narrow, trustworthy tool set that ships is more valuable than a broad, half-validated tool set that doesn't.

---

## 5. How to Propose Scope Changes

If a future session believes a boundary listed here should be reconsidered:

1. **Do not silently expand scope.** Code changes that introduce out-of-scope capability will be rejected.
2. **Write a proposal doc** explaining what is being reconsidered, why, and what has changed since the boundary was set.
3. **Threat model review.** Evaluate the proposal against all 7 threats from [005](005-AT-ADEC-threat-model.md). Document the results.
4. **Safety model impact.** Identify which safety invariants from [003](003-TQ-STND-safety-model.md) are affected and how they will be maintained.
5. **Update this document.** If the proposal is accepted, move the item from out-of-scope to in-scope with a rationale note and date.
6. **Explicit sign-off.** The operator must approve scope changes. No autonomous scope expansion.

---

## 6. Reference Documents

| Document | Relevance |
|----------|-----------|
| [001 — Blueprint](001-PP-PLAN-repo-blueprint.md) | Mission and non-goals (§5) — primary source of permanent boundaries |
| [003 — Safety Model](003-TQ-STND-safety-model.md) | Governing safety spec — rationale for safety-driven boundaries |
| [005 — Threat Model](005-AT-ADEC-threat-model.md) | 7 threats — rationale for attack-surface-driven boundaries |
| [017 — v2 Tool Additions](017-PP-PLAN-v2-tool-additions.md) | v2 plan and "What Is NOT v2" (§5) — source of version-scoped boundaries |
| [019 — Telemetry Emission Hook](019-AT-ADEC-telemetry-emission-hook-interface.md) | Defines how this repo interfaces with ecosystem repos without owning them |
