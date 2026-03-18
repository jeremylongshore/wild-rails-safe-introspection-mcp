# Contributing to wild-rails-safe-introspection-mcp

Thank you for your interest in contributing. This project is currently maintained internally, but we welcome security reports and feedback.

## Current Status

This repository is in **v1 complete** status. The primary focus is:
- Security maintenance
- Bug fixes
- Documentation improvements

New features are tracked via the v2 planning documents in `000-docs/017-PP-PLAN-v2-tool-additions.md`.

## Before Contributing

1. Read `CLAUDE.md` for project context and conventions
2. Read `000-docs/003-TQ-STND-safety-model.md` for safety requirements
3. Read `000-docs/005-AT-ADEC-threat-model.md` for security considerations

## Safety Rules

These are **non-negotiable** when contributing to this codebase:

1. **Never introduce write paths** — No `save`, `create`, `update`, `destroy`, or write SQL
2. **Never bypass the query guard** — All data access goes through the guard
3. **Never skip audit logging** — Every invocation must produce an audit record
4. **Never expose blocked resources** — Denylist columns must be stripped
5. **Never accept arbitrary code as input** — Tool parameters are data, not code
6. **Prefer restrictive defaults** — When uncertain, deny access

## Development Setup

```bash
bundle install              # Install dependencies
bundle exec rspec           # Run test suite (468 tests)
bundle exec rubocop         # Lint
bundle exec ruby bin/validate_deployment  # Smoke test safety controls
```

## Pull Request Process

1. Fork the repository
2. Create a feature branch from `main`
3. Ensure all tests pass: `bundle exec rspec`
4. Ensure no lint errors: `bundle exec rubocop`
5. Update documentation if applicable
6. Submit a pull request with clear description

## Security Contributions

If your contribution addresses a security issue, please coordinate with maintainers privately before submitting a public pull request. See `SECURITY.md` for details.

## Code of Conduct

Please review and follow our `CODE_OF_CONDUCT.md`.

## Questions?

For questions about contributing, open a GitHub issue with the `question` label.
