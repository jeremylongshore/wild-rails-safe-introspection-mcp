# wild-rails-safe-introspection-mcp

Safe, governed, read-only runtime introspection of Rails applications via MCP.

## What This Is

An MCP server that gives AI agents and operators a structured, auditable way to inspect live Rails production state — models, schema, records — without granting raw console access or permitting mutation.

Every tool invocation is:
- **Policy-enforced** — only allowed models and columns are accessible
- **Bounded** — row caps, query timeouts, and scope limits prevent abuse
- **Audited** — every call is logged with caller identity, parameters, and outcome
- **Read-only** — no write paths exist by design

## Part of the Wild Ecosystem

This is the flagship product-facing repo in the [wild](../) ecosystem — a family of repos focused on governed AI operational tooling for Rails production environments.

See `../CLAUDE.md` for ecosystem-level context.

## Status

**Active development** — Epic 3 (Rails adapter) in progress. Epics 1-2 (foundation + safety docs) complete.

- Canonical blueprint: `000-docs/001-PP-PLAN-repo-blueprint.md`
- Build plan: `000-docs/002-PP-PLAN-epic-build-plan.md`
- Safety model: `000-docs/003-TQ-STND-safety-model.md`
- Task tracking: Beads (repo-local, run `bd list` to see current state)

## License

Intent Solutions Proprietary
