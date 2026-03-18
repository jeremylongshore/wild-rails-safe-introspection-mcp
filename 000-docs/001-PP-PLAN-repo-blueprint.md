# wild-rails-safe-introspection-mcp — Repo Blueprint

**Document type:** Canonical repo blueprint
**Filed as:** `001-PP-PLAN-repo-blueprint.md`
**Repo:** `wild-rails-safe-introspection-mcp`
**Status:** Active — v1 complete (all 10 epics implemented and verified)
**Last updated:** 2026-03-17

---

## 1. Purpose

This is the canonical blueprint for `wild-rails-safe-introspection-mcp`.

It defines the repo mission, product vision, non-goals, architecture direction, safety model, and planning expectations before any implementation begins. It is the source of truth for what this repo is, what it will do, and what it will not do.

This document is written for future Claude Code sessions and for the operator. It is not an implementation spec. It is not the epic breakdown. It is the authoritative pre-implementation reference that all later planning and execution must align with.

---

## 2. Repo Mission

`wild-rails-safe-introspection-mcp` provides **safe, governed, read-only introspection of live Rails applications via MCP**.

It gives AI agents and authorized operators a structured, auditable way to inspect production Rails state without granting raw console access or permitting mutation. The tools it exposes are Rails-aware: they understand models, associations, schema, and query patterns in a way that generic database access does not. Every invocation is controlled, logged, and bounded.

The repo is the flagship product-facing surface of the `wild` ecosystem. It establishes the patterns — MCP tool design, safety enforcement, audit trail shape, capability gate integration — that other repos in the ecosystem will follow.

---

## 3. Problem Statement

Engineers routinely need to inspect production Rails state: look up a customer record, verify a feature flag, check a job queue, or understand what a model contains. They do this today through production consoles (Rails console, direct DB access, Datadog, Metabase) — each of which involves real risk:

- Console access is unrestricted. One bad command mutates or destroys data.
- DB access is unmediated. Query mistakes can be expensive or break replicas.
- Most tooling requires human engineers, not AI agents, to be in the loop.
- Usage is rarely audited in a structured, replayable way.

As AI agents take on more operational work — helping engineers, powering support tooling, running diagnostics — they need the same kind of access. But the risk profile of unrestricted agent access is worse, not better, than unrestricted human access. Agents act fast, execute exactly what they are told, and have no intuitive sense of "this looks dangerous."

`wild-rails-safe-introspection-mcp` solves this by providing a governed interface: the agent gets a curated set of safe read-only tools instead of a raw console. The tools are bounded, audited, and policy-aware. The agent can answer "what is happening in production?" without the ability to change anything.

---

## 4. Core Product Vision

The intended product is a Rails-aware, read-only MCP server that any sufficiently authorized AI agent can invoke safely.

**What this means in practice:**

**Rails-aware tools, not raw SQL.**
Tools understand ActiveRecord models, associations, and Rails conventions. The agent queries through structured, model-aware access patterns — not arbitrary SQL.

**Read-replica by default.**
Where infrastructure allows, all queries route to a read replica. This protects primary write capacity and adds a structural guarantee against mutations.

**Model verification before access.**
Before returning records, tools verify the model exists, is safe to access, and is not on a blocked list. No fishing for tables.

**Sensitive resource blocking.**
Certain models, columns, and tables are explicitly blocked from exposure. PII-dense tables, credential stores, and internal audit logs are examples of resources that require policy-level approval before they appear in tool output.

**Row caps, query timeouts, and scope limits.**
No unbounded queries. All tool invocations enforce maximum row counts, query timeouts, and scope restrictions. The tools cannot be weaponized to DDOS the database.

**Audited invocations.**
Every tool call is logged with: who called it, what was asked, what was returned (or denied), and when. The audit trail is the foundation of trust for production access.

**Policy-aware access.**
The server respects policy definitions: which models are accessible, which columns may appear in output, which users/agents may call which tools. Policies are explicit, not implicit.

**Capability gate compatibility.**
The server is designed to work with `wild-capability-gate`. Privileged tools — those with higher-risk query patterns — require gate-approved access before execution.

**Operational debugging, not analytics.**
The tools are designed for "what is happening right now?" questions — inspecting a specific record, verifying state, checking job status — not for running analytics queries across large datasets.

---

## 5. Non-Goals and Boundaries

These boundaries exist to keep the repo focused. Scope creep in the direction of any of these will dilute the repo's safety model and delay a useful v1.

**Not a write-capable production console.**
This repo does not expose write operations in its initial form. No record creation, update, deletion, or migration execution. Read-only, by definition.

**Not arbitrary Ruby/Rails execution.**
The server does not provide a general-purpose Rails console interface. It exposes specific, defined, audited tools. A tool that accepts arbitrary Ruby code and executes it defeats the entire safety model.

**Not an all-in-one admin and support platform.**
Admin operations — running jobs, clearing caches, updating feature flags — belong in `wild-admin-tools-mcp`. This repo reads. That repo acts.

**Not a full analytics platform.**
Aggregation queries, reporting pipelines, and analytics workloads are out of scope. The tools answer operational questions, not business intelligence questions.

**Not a generic ORM for every framework.**
Day one focus is Rails/ActiveRecord. Support for other frameworks (Hanami, Sinatra with Sequel, etc.) is a future extension, not a v1 requirement.

**Not a compliance dashboard product.**
Audit logs generated here are for operational accountability, not for satisfying formal compliance frameworks (SOC2, HIPAA, etc.). Those requirements may inform the design but the repo does not position itself as a compliance product in its initial form.

**Not a kitchen-sink internal tools suite.**
Feature requests that sound like "while we're here, can it also..." belong in a separate repo or a later phase. Ship a narrow, trustworthy v1.

---

## 6. Primary Users and Use Cases

### Users

**Platform and Rails engineers** — using the server to inspect production state safely during incident response, debugging, or operational monitoring.

**Trusted support and ops users** — accessing customer records through a structured, audited interface that avoids full Rails console access.

**AI infrastructure teams** — integrating the server into agent-powered operational workflows where the agent needs to inspect production conditions as part of a larger task.

**Security and compliance reviewers** — using audit trail output to understand what was accessed, when, and by whom.

### High-value early use cases

These are the use cases that define what a credible v1 looks like. If the server handles these well, it is useful:

1. **Inspect a customer or account record safely** — look up a record by ID, see its fields (minus blocked columns), understand its associations.

2. **Verify feature flag state for a user or account** — check whether a flag is enabled, what value it has, and in what context.

3. **Inspect model schema and shape** — understand what columns a model has, what its types are, and which associations are defined, without running a query.

4. **Check a limited record set through a safe filter** — find records matching a controlled predicate (e.g., "accounts created today that are in error state") with row caps enforced.

5. **Inspect job/queue state where supported** — check background job queues, see job status, identify stuck or erroring jobs — through structured tools, not raw DB access.

6. **Answer "what is happening?" operational questions** — support the classic incident-response pattern: "customer X says Y isn't working, can you verify the state of their data?"

---

## 7. Early Architecture Direction

This section describes the expected shape of the system. It is directional — not a final design. Decisions will be refined during the epic breakdown.

### Major components

**MCP server layer**
The outermost surface. Implements the MCP protocol, exposes tool definitions, handles request routing, and enforces session-level controls. This is what clients (agents, CLI tools) connect to.

**Tool registry**
A curated, explicit catalog of available tools. Each tool has: a name, a description, a parameter schema, a safety classification, and a handler. No dynamic or generated tools — all tools are explicitly defined and reviewed.

**Rails adapter layer**
The bridge between tool invocations and Rails/ActiveRecord. Handles model reflection, association traversal, schema introspection, and query execution. Isolates the MCP layer from Rails-specific implementation details.

**Query guard / policy engine**
Enforces access policies before any query reaches the database. Checks: is this model on the allowed list? Are any requested columns blocked? Does this invocation exceed row or time limits? Does the caller have the right capability level?

**Read-replica routing**
Ensures queries route to a read replica when one is configured. Falls back gracefully when no replica is available, but documents the downgrade. Not the repo's job to manage replica configuration — just to use it correctly.

**Audit trail**
Every tool invocation — whether it succeeds, is denied, or errors — produces an audit record. The record captures: caller identity, tool name, parameters (sanitized), outcome, and timestamp. This is not optional.

**Capability gate interface**
A compatibility layer for `wild-capability-gate`. Privileged tools check the gate before executing. The interface is defined against the gate's public contract — not implemented inline in this repo.

### What this is not

Not a general-purpose query engine. Not an admin interface. Not a plugin system (at v1). Not a multi-tenant SaaS. Build the components above and ship something useful.

---

## 8. Safety Model

Safety is the primary design constraint for this repo. Every architecture and implementation decision must be evaluated against it.

**Read-only by design.**
The system has no write paths in v1. This is not a configuration option — it is a design constraint. Write paths do not exist. If a future version introduces controlled writes, that is a major, explicitly reviewed expansion of scope.

**Database-level read enforcement where possible.**
Where infrastructure supports it, connections to the database use read-only credentials. This provides a structural guarantee that goes beyond application-level enforcement.

**Application-level write prevention as defense-in-depth.**
Even when using read-only DB credentials, the Rails adapter layer explicitly refuses any ActiveRecord operation that could trigger a write. Double enforcement is acceptable.

**Allowlist-based model access.**
Models are not accessible by default. Access is granted through an explicit allowlist. Unknown models are refused. New models added to the application do not automatically become accessible — they must be explicitly reviewed and listed.

**Denylist for sensitive resources.**
On top of the allowlist, a denylist blocks access to specific models, columns, and tables that carry elevated sensitivity. The denylist takes precedence over the allowlist. Examples: credential tables, PII-dense models, internal audit log tables, payment data.

**Row caps and query timeouts.**
All queries enforce a maximum row return count (configurable, with a default that is conservative). All queries enforce a wall-clock timeout. Queries that exceed these limits are cancelled and logged, not partially returned.

**Identity and authorization context.**
Every invocation carries an identity: who or what is calling, with what credential or session token. Anonymous invocations are not permitted. The identity is recorded in the audit trail.

**Auditable invocation logging.**
Every tool call produces an audit record regardless of outcome. Successes, denials, timeouts, and errors are all logged. Audit logs are append-only and structured for later analysis.

**Explicit refusal of mutation paths.**
The tool handlers contain no code paths that could trigger write operations. This means: no `save`, `create`, `update`, `destroy`, `delete`, `execute` with write SQL, or equivalent. If such a code path is found during review, it is a security defect.

**Conservative defaults.**
When uncertain between more permissive and more restrictive, choose restrictive. Operators can expand access through policy configuration. Contracting access after exposure is much harder.

---

## 9. Relationship to Other Wild Repos

This repo does not exist in isolation. Understanding its ecosystem connections shapes the architecture.

**`wild-capability-gate`** — The access control layer this repo integrates with for privileged tool execution. The gate's authorization interface must stabilize before this repo's privileged tools can be implemented in production form. Wave 1 dependency: design against the gate's planned interface early; full integration after the gate ships its public contract.

**`wild-admin-tools-mcp`** — The companion repo for write operations and administrative actions. These two repos are intentionally separated so the safety boundary is architectural, not just policy-based. This repo reads; that repo acts. They share MCP server patterns and will likely share some Rails adapter conventions, but they are distinct products.

**`wild-session-telemetry`** — May capture operational usage events from this repo's invocations — tool call patterns, latency, denied access events — as input to the broader observability pipeline. This repo does not depend on the telemetry repo, but can emit events that the telemetry layer picks up.

**`wild-transcript-pipeline`** and **`wild-gap-miner`** — May later analyze transcripts of agent sessions using this server to identify capability gaps: "what did agents try to do that the server couldn't support?" This is a Wave 2–3 concern, not a design constraint for v1.

**`wild-skillops-registry`** — May eventually register this repo's tool catalog as a set of discoverable, versioned capabilities. Not a v1 concern.

---

## 10. Documentation Needs

As implementation proceeds, this repo will need durable supporting documents beyond this blueprint. These should be created as needed — not speculatively in advance — and filed in `000-docs/` per `/doc-filing` conventions.

Anticipated documents:

| Document | Purpose |
|----------|---------|
| Safety model (detailed) | Full spec for the read-only constraint, allowlist/denylist rules, row caps, timeout policies, and audit requirements |
| Architecture overview | Diagrams and descriptions of major components and how they connect |
| Tool catalog | The canonical list of MCP tools this server exposes, with parameter schemas and safety classifications |
| Blocked-resource policy | The policy definition format, how to add/remove models and columns, how denylist precedence works |
| Threat model | Anticipated attack surfaces and mitigations: prompt injection, credential abuse, data exfiltration patterns, query abuse |
| Operator workflow guide | How to deploy, configure, and operate the server in a real Rails production environment |
| Evaluation strategy | How to verify the server is behaving safely and correctly across different Rails applications |
| Glossary / terminology | Definitions of terms used in this repo: tool, guard, policy, audit record, capability level, etc. |

Create these docs when the work demands them. A doc that does not yet have a home in planned work belongs in `planning/notes.md` as a placeholder reference, not in `000-docs/` until the content is substantive.

---

## 11. Planning and Task Model

Before implementation begins, this repo will receive the following planning artifacts in order:

1. **Repo build plan (10 epics)** — a human-readable breakdown of the full repo scope into 10 outcome-oriented epics, each with clear mission, rationale, and child task breakdown
2. **Child tasks** — written in natural language, explaining the purpose of each unit of work and how it contributes to the epic's outcome
3. **Explicit dependency blocks** — between tasks within this repo and across repos where relevant, with prose rationale for why each dependency must be resolved first
4. **Natural-language annotations** — operator notes that provide context, state assumptions, flag blockers, and set evidence expectations for task closure
5. **Beads creation prompt** — a guided prompt for Claude Code to instantiate the full task structure in Beads
6. **Phased implementation prompts** — a set of guided Claude Code prompts for executing each phase, with room for pragmatic implementation choices within defined constraints

No implementation begins before this planning structure is in place.

---

## 12. Natural-Language Planning Standard

All future epics, Beads, annotations, and dependencies for this repo must be written in natural human language that tells the story of what is being built, why it matters, and how the pieces connect.

**The Beads-docs relationship for this repo:**
- Beads track execution — what is happening, in what order, with what outcome
- Docs preserve meaning — why decisions were made, what the safety model requires, what constraints are non-negotiable
- Annotations connect the two — they link tasks to relevant docs and explain the "why" behind the work

**The narrative test:** a person reading the epics and tasks from top to bottom should understand what this server is, what must be built first (safety foundation, then tools, then integration), what the risky design decisions are, and how the work is expected to unfold.

**When to create a supporting document instead of relying on Beads:**
When a concept is too important to leave implicit in a task annotation — a safety policy, an architecture decision, a non-goal that must be preserved — create a document in `000-docs/` and reference it in the relevant task. Beads are not a substitute for durable explanation.

---

## 13. Risks and Design Tensions

These tensions are real. They will surface during implementation and must be managed consciously, not resolved by defaulting to one extreme.

**Usefulness vs. safety.**
A server that refuses everything is perfectly safe and completely useless. A server that allows everything is maximally useful and maximally dangerous. The product lives in the governed middle, and every scope decision must be evaluated on this axis.

**Introspection depth vs. risk exposure.**
Deeper introspection — richer record views, more association traversal, more schema detail — is more useful but increases the surface area for data exfiltration and abuse. Start narrow and earn depth through proven safety.

**Rails-specific power vs. generality.**
Leaning into Rails/ActiveRecord conventions makes the server much more powerful for Rails teams but constrains its applicability elsewhere. v1 is deliberately Rails-specific. Don't compromise Rails-native ergonomics to support hypothetical non-Rails users.

**Operational speed vs. audit rigor.**
Aggressive audit logging adds latency. But an audit trail is the foundation of trust. Optimize for correctness of audit records first; optimize for performance second. Never skip an audit record for performance reasons.

**Product simplicity vs. platform ambition.**
There is a version of this repo that becomes a comprehensive production intelligence platform. That is not v1. v1 is a narrow, trustworthy, credible MCP server with a curated tool set. Platform ambitions belong in the backlog, not the v1 scope.

---

## 14. MVP Recommendation

A realistic, credible v1 should do the following and nothing more:

**Controlled record lookup by ID.**
Given a model name and a record ID, return the record's fields (minus blocked columns) up to a configured row limit. Verify the model is allowed. Log the invocation.

**Model schema inspection.**
Given a model name, return its column names, types, and associations — no records. This is low-risk and high-utility for agents that need to understand data shape before forming queries.

**Filtered record lookup with guardrails.**
A single filter predicate (one field, one value) against an allowed model. Row cap enforced. Timeout enforced. This covers the "find me accounts in error state" class of questions.

**Audit logging from day one.**
Every invocation — including the schema inspection and record lookup above — produces an audit record. This is not a later phase. It ships with the first tools.

**Blocked model/column enforcement.**
The denylist is in place from day one. No sensitive resources slip through because the policy engine "isn't implemented yet."

**Basic policy allowlist.**
A configuration-driven allowlist of models that are accessible. Ships with a minimal default set and a clear mechanism to add more.

**Strong documentation and evaluation posture.**
The safety model doc is written before the code ships. The tool catalog is written concurrently. The operator workflow guide exists before anyone tries to deploy it.

**What v1 explicitly does not include:** arbitrary query predicates, association traversal, aggregation queries, cross-model joins, write paths, capability gate integration (designed for but not required to ship), telemetry integration.

---

## 15. Current Status

This repo is in **blueprint and planning mode only**.

No application code exists. No Beads have been created. No GitHub repo has been initialized. No CI/CD has been configured.

This blueprint document is the first canonical planning artifact for the repo. The next step is the 10-epic breakdown.

---

## 16. Immediate Next Step

The next planning step for this repo is:

1. **Convert this blueprint into a 10-epic build plan** — each epic covering a major outcome area with human-readable mission, rationale, and child task breakdown
2. **Define child tasks and dependency blocks** — in natural language, with prose rationale for ordering
3. **Prepare the Beads creation prompt** — a guided Claude Code prompt that instantiates the full task structure
4. **Then begin phased repo execution** — one epic at a time, with evidence-backed task closure at each step

Do not begin implementation until the Beads structure is in place and the operator has reviewed the epic breakdown.
