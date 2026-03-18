# wild-rails-safe-introspection-mcp — 10-Epic Build Plan

**Document type:** Canonical repo build plan
**Filed as:** `002-PP-PLAN-epic-build-plan.md`
**Repo:** `wild-rails-safe-introspection-mcp`
**Status:** Active — v1 complete (all epics implemented and verified)
**Last updated:** 2026-03-17
**Blueprint reference:** `001-PP-PLAN-repo-blueprint.md`

---

## 1. Purpose

This is the canonical 10-epic build plan for `wild-rails-safe-introspection-mcp`.

It translates the repo blueprint into an implementation-ready execution story. This document is not Beads. It is not code. It is the structured, narrative planning layer between the blueprint (what we are building and why) and Beads (how we track doing it). When Beads are created, they must be faithful to this plan.

---

## 2. Planning Intent

The blueprint defines what this server is and what it must not become. This plan defines the order in which it gets built, why that order is correct, and what each phase must produce before the next phase starts.

The plan is written for two audiences:

**Future Claude Code sessions** — who need to understand the build narrative before touching code, and who must resist the temptation to skip ahead.

**The operator (Jeremy)** — who needs to be able to open this document at any point and understand exactly where the repo is in its story.

Every epic here earns the right to exist. The ordering is not arbitrary.

---

## 3. Sequencing Logic

The build sequence follows a simple principle: **earn the right to expose power before you expose it**.

The stack is built from the ground up:

1. **Foundation first** — repo structure, planning docs, CLAUDE.md, README. Nothing else can happen without a clean working environment.

2. **Safety posture before code** — the safety model, threat model, and policy format are written as documents before a single line of implementation is produced. The rules come before the engine.

3. **Data access layer before the query guard** — the Rails adapter needs to exist as a raw capability before the policy layer wraps it. But the adapter is built to be safe by design, not patched safe later.

4. **Query guard before audit** — the policy engine is in place before audit logging, because the audit records must capture policy enforcement outcomes (denied, allowed, capped), not just raw calls.

5. **Audit before identity** — the audit trail's shape is defined before identity/auth, so the identity system knows what it must produce for the trail.

6. **Identity before the MCP surface** — no client-facing surface until the auth layer exists. The MCP server is built on top of a working auth and audit stack, not the other way around.

7. **MCP surface after the full stack** — when tools are exposed to agents, they sit on top of a complete pipeline: adapter → guard → audit → auth → MCP.

8. **Safety testing before MVP** — before anything is called "ready," the safety model is proven. Not assumed. Tested adversarially.

9. **Operator packaging before release** — the docs and deployment story exist before any real operator tries to run this.

10. **Expansion readiness closes the v1 story** — the architecture's extension points are documented so the repo can grow without drifting.

---

## 4. The 10 Epics

---

### Epic 1 — Lay the Repo Foundation So All Future Work Has a Clean Home

**Epic mission:**
Establish the development-ready structure for this repo: directory layout, working CLAUDE.md with repo-specific operating rules, README, and any planning scaffolding needed before implementation begins. When this epic is done, a Claude Code session can open the repo and know exactly what it is, where things go, and what rules apply.

**Why this epic comes first:**
Nothing else works well without it. If the CLAUDE.md doesn't reflect the repo's actual conventions, future sessions will make wrong assumptions. If the directory structure isn't established, docs and code end up in random places. The cost of doing this first is low. The cost of not doing it is paid repeatedly.

**Scope of this epic:**
- Create the final production-grade `CLAUDE.md` for this repo with specific conventions: language/runtime, directory layout, testing approach, safety rules, what not to touch
- Finalize the `README.md` with a clear one-paragraph mission, status indicator, and pointer to canonical docs
- Establish the top-level directory structure: `src/`, `tests/`, `config/`, `000-docs/`, `planning/`
- Update `planning/epics.md` to point to this canonical plan (it is currently a stub)
- Confirm all existing planning docs are correctly indexed in `000-docs/`

**Out of scope for now:**
Any application code. Any gem/dependency management. Any CI/CD configuration.

**Likely child-task themes:**
- Write the repo-specific CLAUDE.md (language choices, test framework, file layout, safety rules)
- Update the README to reflect the current planning state
- Create top-level directory structure
- Update `planning/epics.md` to reference this doc
- Verify `000-INDEX.md` is current

**Dependency notes:**
Depends on nothing. Everything else depends on this. Do not start any other epic until Epic 1 is closed.

**Supporting docs to create/reference:**
- `001-PP-PLAN-repo-blueprint.md` is the governing reference — CLAUDE.md must be consistent with it

**Narrative annotation:**
This is the scaffolding pass before the interesting work begins. It takes one focused session. The reward is that every subsequent session can start from a known-good state instead of guessing.

---

### Epic 2 — Write the Safety Rules Down Before Writing Any Code

**Epic mission:**
Produce the canonical safety model document for this repo — the durable, explicit specification of what the server will and will not do from a safety and trust perspective. This document becomes the governing reference for all implementation decisions. It must exist before any code is written, because code that precedes the safety spec will be built against ambiguity.

**Why this epic comes second:**
The repo's entire value proposition is that it is safe. If the safety rules exist only in the blueprint's prose and in intentions, they will drift during implementation. Making the safety model a standalone document that can be reviewed, contested, and referenced creates accountability. Engineers (or future Claude Code sessions) who encounter a tricky decision can check the safety doc rather than guessing.

**Scope of this epic:**
- Write `003-TQ-STND-safety-model.md`: the detailed safety model specification covering read-only enforcement, allowlist/denylist structure, row caps, timeout policy, identity requirements, audit requirements, and conservative defaults
- Write `004-TQ-STND-blocked-resource-policy.md`: how the denylist is defined, what format policy files use, how precedence works between allowlist and denylist, examples
- Write `005-AT-ADEC-threat-model.md`: the anticipated attack surfaces (prompt injection, credential abuse, data exfiltration, query abuse) and how the architecture mitigates each one
- Capture and decide the major architecture decisions that safety implies: What is the read-only credential contract? What happens when no read-replica is available? What does a denied invocation look like to the caller?

**Out of scope for now:**
Implementation of any of these rules. The policies are written but no code enforces them yet.

**Likely child-task themes:**
- Draft the safety model document and get it reviewed by the operator before marking complete
- Define the allowlist and denylist policy format with concrete examples
- Write the initial threat model covering the four primary attack surfaces
- Make and record key architecture decisions (credential model, replica fallback behavior, denial response format)

**Dependency notes:**
Depends on Epic 1 (clean repo structure and CLAUDE.md to know where docs go and what standards apply). All implementation epics (3–9) depend on this epic being closed — they implement what this epic specifies.

**Supporting docs to create/reference:**
- `003-TQ-STND-safety-model.md` — main deliverable of this epic
- `004-TQ-STND-blocked-resource-policy.md` — policy format deliverable
- `005-AT-ADEC-threat-model.md` — threat surface deliverable

**Narrative annotation:**
This epic is the most important planning work in the repo. It is not glamorous. It does not produce running code. But a system whose safety rules are written down and signed off is a fundamentally different thing from a system whose safety is assumed to be somewhere in the code. Do not skip or rush this epic.

---

### Epic 3 — Build the Rails Adapter: Safe Data Access From the Ground Up

**Epic mission:**
Implement the Rails adapter layer — the component that bridges tool invocations to Rails/ActiveRecord. This layer provides the raw capabilities that the policy engine will later wrap: model reflection, schema introspection, safe record lookup by ID, and safe filtered record lookup. The adapter is built to be read-safe by construction, not patched safe after the fact.

**Why this epic comes third:**
The policy engine (Epic 4) needs something to enforce policy against. The audit trail (Epic 5) needs something to record invocations about. The MCP tools (Epic 7) need something to invoke. The adapter is the foundational data access layer. Everything above it depends on it. But the adapter itself has no dependencies on the layers above it, so it is the right thing to build first in the implementation stack.

**Scope of this epic:**
- Model reflection: given a model name string, check whether the model exists in the Rails app and return its basic metadata
- Schema introspection: given a model name, return columns (name, type, nullable) and associations (name, type, target) without executing any data query
- Safe record lookup by ID: given a model name and a record ID, return the record as a hash — no write operations, no side effects
- Safe filtered record lookup: given a model name and a single field/value predicate, return matching records as an array of hashes — no write operations
- Defense-in-depth write prevention: explicit checks that refuse any operation that could trigger a write, even if called incorrectly by layer above
- Read-replica routing: route queries to a read replica when configured; fall back gracefully and log the fallback

**Out of scope for now:**
Policy enforcement (that's Epic 4). Audit logging (that's Epic 5). Auth (that's Epic 6). Multi-predicate filtering. Association traversal. Aggregation. Arbitrary SQL.

**Likely child-task themes:**
- Implement model reflection (existence check + metadata)
- Implement schema introspection (columns + associations)
- Implement safe record-by-id lookup
- Implement safe filtered lookup (single predicate, returns array)
- Implement explicit write prevention guards
- Implement read-replica routing with graceful fallback
- Write unit tests for each component against a real test Rails app schema

**Dependency notes:**
Depends on Epics 1 (repo structure) and 2 (safety model doc, so the adapter knows what "safe" means for its write prevention logic). The policy engine (Epic 4), audit trail (Epic 5), and all later epics depend on this.

**Supporting docs to create/reference:**
- `003-TQ-STND-safety-model.md` (from Epic 2) governs the write prevention requirements
- Consider starting `006-AT-ARCH-architecture-overview.md` during this epic to capture component diagrams as they emerge

**Narrative annotation:**
The adapter is deliberately narrow. It is not a query engine. It does not have a query builder. It has four capabilities: reflect on a model, inspect its schema, look up a record by ID, and filter records by one predicate. That's it. Resist the temptation to add more here. The simplicity of the adapter is part of the safety story.

---

### Epic 4 — Build the Query Guard: No Query Reaches the Database Without Passing Policy

**Epic mission:**
Implement the query guard and policy engine — the layer that wraps every adapter call with access policy enforcement before it runs. No query reaches the database without passing through the guard. The guard enforces the allowlist, applies the denylist, strips blocked columns from results, enforces row caps, and enforces timeouts. When this epic is done, the system has a working, testable access control layer.

**Why this epic comes fourth:**
The adapter (Epic 3) provides raw data access. Without the guard, that access is unsafe: any model could be queried, any column could be returned, queries could run forever. The guard is what makes the adapter safe to use. But the guard cannot be built until the adapter exists, because the guard wraps the adapter's interface.

**Scope of this epic:**
- Allowlist check: given a model name, verify it is in the configured allowlist; return a clear denial if not
- Denylist check: given a model name and requested columns, verify none are on the denylist; strip or deny as configured
- Column filter: strip blocked columns from results before they leave the guard; the caller never sees them
- Row cap enforcement: wrap filtered lookups with a configurable maximum row count; cancel and log if exceeded
- Query timeout enforcement: wrap all adapter calls with a configurable wall-clock timeout; cancel and log if exceeded
- Policy configuration format: define how the allowlist and denylist are expressed in configuration files, consistent with `004-TQ-STND-blocked-resource-policy.md`
- Clear denial responses: when the guard denies a request, the response must clearly state why (model not allowed, column blocked, row cap exceeded, timeout) without revealing information that shouldn't be revealed

**Out of scope for now:**
Audit logging (that's Epic 5). Identity-based policy variations (that's Epic 6 and later). Multi-predicate policies. Dynamic policy updates at runtime.

**Likely child-task themes:**
- Implement allowlist check with clear denial message
- Implement denylist check and column stripping
- Implement row cap enforcement (configurable, with safe default)
- Implement query timeout wrapper (configurable, with safe default)
- Implement policy file loading and validation
- Write tests: allowed model passes, blocked model denies, blocked column stripped, row cap triggers, timeout triggers

**Dependency notes:**
Depends on Epic 3 (the adapter to wrap) and Epic 2 (the safety model and policy format docs that define what the guard must enforce). The audit trail (Epic 5) depends on this being in place so it can record guard outcomes.

**Supporting docs to create/reference:**
- `004-TQ-STND-blocked-resource-policy.md` (from Epic 2) is the governing spec for policy format
- Update `006-AT-ARCH-architecture-overview.md` with the guard's position in the stack

**Narrative annotation:**
The guard is where the safety model becomes real code. The safety doc says "models are allowlisted" — the guard is what actually checks the allowlist. The safety doc says "row caps are enforced" — the guard is what enforces them. The relationship between the safety model doc and this epic is direct and testable: every rule in the safety doc should have a test in this epic that proves the rule is implemented.

---

### Epic 5 — Build the Audit Trail: Every Invocation Leaves a Record

**Epic mission:**
Implement the audit trail — the append-only structured log of every tool invocation, regardless of outcome. Successes, denials, timeouts, and errors all produce audit records. The audit trail is the mechanism that makes this server trustworthy: operators can see what was accessed, what was denied, and when. Without this, the server is a black box. With it, the server is accountable.

**Why this epic comes fifth:**
The audit trail needs to capture outcomes from the query guard (denied, allowed, capped, timed out), which means it wraps the guard. The audit trail also needs an identity to record (who made this call), but the full identity system comes in Epic 6. For now, the audit record schema is designed to accept an identity field, and the field is populated with whatever is available from the session context. The identity system in Epic 6 will make this richer.

**Scope of this epic:**
- Audit record schema: define the structure of an audit record — timestamp, caller identity (placeholder until Epic 6), tool name, model name, parameters (sanitized), policy outcome, result summary, duration
- Append-only storage: audit records are written and never modified; define the storage backend (file, DB table, or structured log — decide and document)
- Parameter sanitization: before recording parameters, strip any values that should not appear in logs (e.g., raw record contents are summarized, not logged in full)
- Outcome capture: capture whether the call succeeded, was denied by the guard, timed out, or errored — and which specific rule triggered a denial
- Audit record access: a way to read recent audit records for review — not a full UI, but a minimal inspection capability
- Every adapter call routes through the guard and the audit trail before returning — no bypasses

**Out of scope for now:**
The full identity system (that's Epic 6). A UI for audit log review. Analytics on audit data. Export to external SIEM or log aggregation. Telemetry integration.

**Likely child-task themes:**
- Design and implement the audit record schema
- Choose and implement the storage backend (log this choice in an ADR)
- Implement parameter sanitization
- Implement outcome capture from guard results
- Wire the audit trail into the full call pipeline (adapter → guard → audit → response)
- Write tests: every call type produces an audit record; denied calls produce correct denial records; no call bypasses auditing

**Dependency notes:**
Depends on Epics 3 (adapter) and 4 (guard) — the audit trail wraps both of them. Epic 6 (identity) will enrich the audit records. Epic 7 (MCP server) will rely on the audit trail being in place before any tools are exposed.

**Supporting docs to create/reference:**
- Create `007-AT-ADEC-audit-trail-storage-decision.md` to record the storage backend choice and rationale
- `003-TQ-STND-safety-model.md` specifies what audit logging must capture

**Narrative annotation:**
The audit trail is not a nice-to-have that gets added later. It ships with the first tools. A server that allows introspection without an audit trail is just an ungoverned query interface. The audit trail is what transforms this from "a tool that reads data" into "a governed introspection service." There is no v1 without it.

---

### Epic 6 — Establish Identity and Authorization: No Anonymous Access

**Epic mission:**
Implement the identity and authorization layer — the mechanism that ensures every invocation carries a known caller identity, that anonymous calls are rejected, and that caller identity flows through to the audit trail. Also design the capability gate interface so privileged tools know how to check the gate when it becomes available, even if the gate itself hasn't shipped yet.

**Why this epic comes sixth:**
The audit trail (Epic 5) needs an identity to record. The MCP server (Epic 7) needs an auth layer to enforce before routing requests to tools. Identity is the binding layer between the call and the audit record. It must exist before the server surface, because a server without auth is an unauthenticated production introspection endpoint.

**Scope of this epic:**
- Caller identity extraction: given an inbound request (MCP session context), extract the caller's identity — token, service account, or configured credential
- Anonymous rejection: requests without a resolvable identity are rejected before reaching the adapter or guard; the rejection is logged
- Identity propagation: the resolved identity flows through the entire call pipeline — it is present when the guard runs and when the audit record is written
- Session context: design the session context object that carries identity, capability level, and request metadata through the call pipeline
- Capability gate interface: define the interface that privileged tools will use to check `wild-capability-gate` — even if the gate isn't available yet, the interface is stubbed so future integration is a drop-in, not a redesign
- Auth configuration: how callers are configured (API key, token, service account) is documented and the configuration format is defined

**Out of scope for now:**
Integrating with the actual `wild-capability-gate` repo (that's Epic 10 or a future phase). Multi-tenant identity management. OAuth flows. Role-based access control beyond capability levels.

**Likely child-task themes:**
- Design and implement the session context object
- Implement caller identity extraction and validation
- Implement anonymous request rejection
- Wire identity into the audit trail (Epic 5 audit records now get real identity values)
- Define and stub the capability gate interface
- Write tests: authenticated call succeeds; anonymous call is rejected; rejected call is audited; identity appears correctly in audit record

**Dependency notes:**
Depends on Epics 3, 4, 5 (the full adapter → guard → audit stack). Epic 7 (MCP server) depends on this — no client surface ships without auth. The capability gate integration in Epic 10 depends on the interface designed here.

**Supporting docs to create/reference:**
- `008-AT-ADEC-identity-and-auth-model.md` — document the auth model: what identities look like, how they are validated, what happens on rejection
- `009-AT-ADEC-capability-gate-interface.md` — document the stub interface designed for `wild-capability-gate` integration

**Narrative annotation:**
This epic is what turns an interesting piece of software into a trustworthy production tool. After this epic closes, every call to the server has an identity attached to it, every denial has a caller attributed to it, and the audit trail is complete. The server is now ready for its public face.

---

### Epic 7 — Build the MCP Server and Define the v1 Tool Surface

**Epic mission:**
Build the MCP server — the client-facing layer that implements the MCP protocol, registers the curated v1 tool set, routes incoming requests through the full pipeline (identity → guard → adapter → audit), and returns structured responses. When this epic closes, an AI agent can connect to the server and invoke tools against a real Rails application. This is the first moment the repo is demonstrably useful.

**Why this epic comes seventh:**
The MCP server is the top of the stack. It can only be built after everything below it — the adapter (3), the guard (4), the audit trail (5), and the identity layer (6) — are all in place. Building the server earlier would mean building a surface that's not yet safe to expose. Building it now means the first time an agent can reach the server, it already has the full safety stack underneath it.

**Scope of this epic:**
- MCP protocol implementation: implement the MCP server using the appropriate SDK or library; handle session lifecycle, tool discovery, and request routing
- Tool registry: an explicit, curated list of v1 tools, each with a name, description, parameter schema, and safety classification
- v1 tool set (exactly these, nothing more):
  - `inspect_model_schema`: given a model name, return columns and associations
  - `lookup_record_by_id`: given a model name and ID, return the record (policy-enforced)
  - `find_records_by_filter`: given a model name and a single field/value predicate, return matching records (policy-enforced, row-capped)
- Request routing: inbound tool calls are routed through identity check → guard → adapter → audit → response
- Tool response format: consistent, structured response format for success, denial, timeout, and error outcomes
- Connection configuration: how agents configure a connection to this server (host, port, auth token)

**Out of scope for now:**
Additional tools beyond the v1 set. Dynamic tool generation. Plugin system. Multi-tenant routing. Streaming responses. Association traversal. The capability gate check on privileged tools (interface is stubbed but full gate isn't integrated yet).

**Likely child-task themes:**
- Set up MCP server with protocol handling
- Implement tool registry with the three v1 tools
- Wire the full request pipeline (identity → guard → adapter → audit → response)
- Implement structured response format (success, denied, timed out, error)
- Write integration tests: an agent can connect, discover tools, call each tool, and receive correct responses including denial and error cases

**Dependency notes:**
Depends on all of Epics 1–6. This epic's output (a running server) is what Epic 8 (safety testing) will test adversarially.

**Supporting docs to create/reference:**
- `010-DR-REFF-tool-catalog.md` — write the canonical tool catalog: each tool's name, what it does, parameter schema, safety classification, and any constraints. This is the external-facing reference.
- Update `006-AT-ARCH-architecture-overview.md` with the complete system diagram now that all layers exist

**Narrative annotation:**
Epic 7 is the payoff of Epics 1–6. The work done in those epics has been invisible to any external observer. This epic is where the server becomes real. When it closes, an AI agent can ask "what columns does the User model have?" and get an audited, policy-enforced answer. That's the product. Keep the v1 tool set narrow. Three tools, done correctly, are better than ten tools built on a wobbly foundation.

---

### Epic 8 — Prove the Safety Model Holds: Testing, Adversarial Validation, and Evaluation Strategy

**Epic mission:**
Before calling anything "ready," prove that the safety model actually works as specified. This is not routine testing — it is adversarial validation. The goal is to actively try to break the safety claims: try to write data, try to access blocked models, try to exfiltrate data through blocked columns, try to bypass row caps, try to inject malicious queries through the tool parameter interface. If any safety claim fails a test, that is a defect, not a surprising edge case.

**Why this epic comes eighth:**
The server is built. The safety model is documented. Before any real operator tries to run this, the safety claims need to be proven. Shipping without this validation means the safety model is theoretical. The evaluation strategy doc written here becomes the ongoing standard for proving new releases are still safe.

**Scope of this epic:**
- Adversarial write attempts: confirm that no tool invocation, no matter how malformed, can trigger a write operation — test every code path that touches the database
- Blocked model access: confirm that models not on the allowlist cannot be accessed through any tool, including attempts to guess or enumerate model names
- Blocked column exfiltration: confirm that denylist columns are stripped from all responses and that no format variation (aliased column names, serialized fields) can bypass the filter
- Row cap bypass: confirm that crafted queries cannot return more rows than the cap allows
- Timeout bypass: confirm that slow or adversarial queries are always cancelled within the timeout window
- Prompt injection: confirm that tool parameters are treated as data, not code — a parameter value that looks like a Rails expression or SQL fragment must not be evaluated
- Anonymous access: confirm that all unauthenticated calls are rejected and logged
- Policy violation logging: confirm that every safety violation produces the correct audit record
- Evaluation strategy document: produce the document that describes how to run these checks against new releases or new Rails apps

**Out of scope for now:**
Performance benchmarking. Load testing. Penetration testing by external parties. SIEM integration.

**Likely child-task themes:**
- Write the adversarial test suite (one test per safety claim)
- Test write prevention across all adapter call paths
- Test allowlist enforcement: valid model passes, invalid model denies
- Test denylist column stripping
- Test row cap and timeout enforcement under adversarial conditions
- Test prompt injection attempts through tool parameters
- Write and file `011-TQ-SECU-evaluation-strategy.md`

**Dependency notes:**
Depends on Epic 7 (the full server). All safety claims are tested against the complete, integrated system, not individual components. Epic 9 (MVP packaging) cannot close until this epic confirms no safety defects are outstanding.

**Supporting docs to create/reference:**
- `011-TQ-SECU-evaluation-strategy.md` — the evaluation protocol: what is tested, how to run the tests, what a passing result looks like, what constitutes a safety defect

**Narrative annotation:**
This is the checkpoint that determines whether the server is actually safe or just claims to be safe. Every time a new version is released, a new Rails application is connected, or a new tool is added, the evaluation strategy from this epic is the playbook for re-proving safety. Do not let this become a formality. Run the adversarial tests as aggressively as you can design them. A defect found here is a defect caught before it reaches production.

---

### Epic 9 — Package the MVP: Operator Docs, Deployment Story, and End-to-End Validation

**Epic mission:**
Make the server usable by a real operator. The code may work, but without deployment instructions, an operator workflow guide, and an end-to-end validation path, the server is still a lab experiment. This epic produces the documentation and configuration story that transforms a working codebase into a deployable, operable product. When this epic closes, a Rails platform engineer who has never seen this codebase should be able to set up, configure, and connect to the server in a reasonable amount of time.

**Why this epic comes ninth:**
Shipping something useful requires more than working code. An operator who deploys the server incorrectly, connects to the wrong database, or misconfigures the allowlist will not have a safe or useful experience. This epic makes the gap between "the code works" and "an operator can use it" as small as possible.

**Scope of this epic:**
- Operator deployment guide: how to add this server to a Rails application — dependencies, configuration, startup, connection testing
- Configuration reference: every configurable parameter (allowlist, denylist, row cap, timeout, auth tokens, read-replica URL) with its type, default, and behavior when set incorrectly
- Operator workflow guide: the day-to-day operations story — how to add a new allowed model, how to block a column, how to revoke access, how to inspect audit logs
- End-to-end validation: a working demo or test fixture that connects a test Rails app to the server and exercises all three v1 tools, producing verifiable output
- `README.md` update: the README should now reflect the current state of the server — it is a working v1, not a planning placeholder

**Out of scope for now:**
Multi-application deployment. Cloud deployment guides (e.g., Heroku, Fly, Railway). Managed hosting. Monitoring dashboards.

**Likely child-task themes:**
- Write the operator deployment guide
- Write the full configuration reference
- Write the operator workflow guide (add model, block column, revoke access, inspect audit logs)
- Produce the end-to-end validation demo/fixture
- Update the README to reflect v1 status

**Dependency notes:**
Depends on Epics 7 (the server exists) and 8 (the server is validated as safe). Cannot close until the operator docs are tested by actually following them — docs that only work in theory are not done.

**Supporting docs to create/reference:**
- `012-OD-OPNS-operator-deployment-guide.md`
- `013-DR-REFF-configuration-reference.md`
- `014-OD-GUID-operator-workflow-guide.md`

**Narrative annotation:**
The temptation at this stage is to cut corners on docs because the code is working and the interesting problems feel solved. Resist it. The operator docs are the final gate before real Rails engineers point this at production systems. An undocumented server is an unsafe server — not because the code is wrong, but because operators will misconfigure it when they can't find the answers they need.

---

### Epic 10 — Preserve the Architecture and Define What Comes Next Without Exploding the Scope

**Epic mission:**
Document the controlled expansion roadmap: what the server is ready to support after v1, what architectural extension points exist, how the capability gate will integrate when it ships, and what the clear boundary is between v1 and future versions. When this epic closes, the repo has a written commitment to where it can go without scope explosion, and anyone picking up the repo in the future knows which extensions are planned and which are out of scope.

**Why this epic comes last:**
Expansion only makes sense after the foundation is proven. Documenting the expansion roadmap now — while the architecture is fresh and the trade-offs are understood — prevents future sessions from either expanding recklessly or refusing to evolve. This epic is the bridge between a completed v1 and a responsibly evolving product.

**Scope of this epic:**
- Capability gate integration: document exactly how `wild-capability-gate` will be integrated when it ships — the stub interface from Epic 6 becomes a real integration plan
- Planned v2 tool additions: specify which additional tools are in scope for a v2 (e.g., multi-predicate filtered lookup, limited association traversal) and what safety review they require
- Architecture extension points: document where the system is designed to accept new tools, new policy types, or new identity providers without breaking the existing safety model
- Telemetry emission hooks: define the interface for emitting usage events to `wild-session-telemetry` when that repo is ready
- Explicit out-of-scope list: confirm what is permanently out of scope for this repo (write paths, arbitrary Ruby, analytics, compliance dashboard) so future sessions don't relitigate these decisions

**Out of scope for now:**
Actually implementing any of the v2 features. Integrating with the capability gate (until it ships). Building telemetry emission (until `wild-session-telemetry` ships its interface).

**Likely child-task themes:**
- Write the `wild-capability-gate` integration plan (to be executed when the gate ships)
- Document planned v2 tool additions with their safety review requirements
- Document architecture extension points
- Document the telemetry emission hook interface
- Write and file the confirmed out-of-scope list

**Dependency notes:**
Depends on all prior epics. Informs the planning of `wild-capability-gate` (cross-repo dependency) and `wild-session-telemetry` (future integration). Should be shared with the ecosystem-level planning context when complete.

**Supporting docs to create/reference:**
- `015-PP-PLAN-v2-expansion-roadmap.md` — controlled expansion roadmap
- `016-AT-ADEC-capability-gate-integration-plan.md` — integration plan for when the gate is ready
- Update `001-PP-PLAN-repo-blueprint.md` if the v1 experience has surfaced any blueprint corrections

**Narrative annotation:**
The final epic is not about building — it is about preserving clarity. When this closes, the v1 story is done and the future story is written. A future session picking up this repo should be able to understand immediately: what is built, what is proven, what is next, and what will never be in scope. That is what makes a repo maintainable over time rather than just complete at a moment in time.

---

## 5. Cross-Epic Dependency Summary

The dependency flow through this repo is a single directed chain, with one cross-cutting dependency:

```
Epic 1 (Foundation)
  └── Epic 2 (Safety Model Docs)
        └── Epic 3 (Rails Adapter)
              └── Epic 4 (Query Guard)
                    └── Epic 5 (Audit Trail)
                          └── Epic 6 (Identity & Auth)
                                └── Epic 7 (MCP Server)
                                      └── Epic 8 (Adversarial Testing)
                                            └── Epic 9 (MVP Packaging)
                                                  └── Epic 10 (Expansion Readiness)
```

The only meaningful cross-epic dependency that does not follow the chain is:

**Epic 6 → Epic 10 (capability gate interface):** The stub interface designed in Epic 6 is the contract that the capability gate integration in Epic 10 must match. If the stub is wrong, the integration plan will be wrong. This should be reviewed when Epic 10 is executed.

**Cross-repo dependency:** Epic 10's integration plan depends on `wild-capability-gate` shipping a stable public interface. Until that happens, Epic 10's capability gate tasks are planning artifacts, not executable work.

---

## 6. Document-Backed Execution Notes

The following documents need to exist alongside the implementation work. They are not optional appendages — they are what makes the work trustworthy and maintainable.

| When | Document | Epic | Why it matters |
|------|----------|------|----------------|
| Before any code | Safety model | Epic 2 | Governs every implementation decision |
| Before any code | Blocked-resource policy | Epic 2 | Defines the policy format the guard will implement |
| Before any code | Threat model | Epic 2 | Identifies what the system must defend against |
| During adapter build | Architecture overview | Epic 3+ | Captures component shape as it emerges |
| During guard build | Policy format examples | Epic 4 | Makes the policy format real with examples |
| During audit build | Audit storage ADR | Epic 5 | Records the storage backend decision and why |
| During identity build | Auth model doc | Epic 6 | Defines identity contract for future integrations |
| During identity build | Capability gate interface | Epic 6 | Defines the stub for future gate integration |
| With the MCP surface | Tool catalog | Epic 7 | External reference for agents using the server |
| Before MVP | Evaluation strategy | Epic 8 | The playbook for proving safety on every release |
| With the MVP | Operator deployment guide | Epic 9 | Required for any operator to use this |
| With the MVP | Configuration reference | Epic 9 | Required for safe operator configuration |
| With the MVP | Operator workflow guide | Epic 9 | Required for ongoing operation |
| Closing v1 | v2 expansion roadmap | Epic 10 | Defines what comes next without scope explosion |
| Closing v1 | Capability gate integration plan | Epic 10 | Cross-repo contract for future integration |

---

## 7. Readiness for Beads

This plan is complete. The next step is to convert it into Beads.

When Beads are created:

1. **Create one epic-level Beads entry per epic** — using the epic title and mission as the Beads description
2. **Create child tasks under each epic** — drawn from the "likely child-task themes" sections, written in natural human language that explains the purpose of each task
3. **Attach dependency blocks** — between tasks where the ordering matters, with prose rationale explaining why
4. **Write annotations** — operator-grade notes that give context, state assumptions, and set evidence expectations for task closure
5. **Do not collapse planning detail** — the richness of this plan should be preserved in the Beads, not summarized away

The Beads creation prompt for this repo should reference this document as the governing planning source. Any task that contradicts this plan is wrong and should be corrected before execution begins.
