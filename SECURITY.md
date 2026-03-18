# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in `wild-rails-safe-introspection-mcp`, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

### How to Report

1. Email security concerns to the maintainer privately
2. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact assessment
   - Any suggested mitigations

### What to Expect

- Acknowledgment within 48 hours
- Initial assessment within 7 days
- Regular updates on remediation progress
- Credit in the security advisory (if desired)

## Security Model

This project implements a defense-in-depth safety model documented in `000-docs/003-TQ-STND-safety-model.md`. Key security properties:

### Enforced Boundaries

1. **Read-only** — No write operations exist in the codebase
2. **Policy-enforced** — Model allowlist, column denylist, blocked resource rejection
3. **Bounded** — Row caps (default 50, ceiling 1000), query timeouts (default 5s, ceiling 30s)
4. **Audited** — Every invocation logged with identity, parameters, outcome
5. **Identity-required** — API key validation with constant-time comparison

### Threat Model

Seven threat categories are formally evaluated in `000-docs/005-AT-ADEC-threat-model.md`:

1. Prompt injection through tool parameters
2. Credential abuse and unauthorized access
3. Data exfiltration through allowed channels
4. Query abuse (resource exhaustion)
5. Model and schema enumeration
6. Audit trail tampering or bypass
7. Configuration tampering

### Security Defect Definition

A security defect is any behavior that:
- Allows mutation of data (violates read-only)
- Exposes blocked resources (violates denylist)
- Bypasses identity requirements
- Allows unbounded queries (violates row caps or timeouts)
- Skips audit logging

## Responsible Disclosure

We follow responsible disclosure practices. If you report a vulnerability:
- We will work with you to understand and resolve the issue
- We will credit you in the security advisory (unless you prefer anonymity)
- We ask that you give us reasonable time to address the issue before public disclosure
