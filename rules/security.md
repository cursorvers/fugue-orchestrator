# Security Rules

## Principle

**Always run security checks before commit.**

## Required Checklist

| # | Item | Check |
|---|------|-------|
| 1 | No hardcoded secrets | API keys, passwords, tokens not in code? |
| 2 | Input validation | All inputs validated with Zod or similar? |
| 3 | SQL injection prevention | Using parameterized queries? |
| 4 | XSS prevention | HTML sanitized? |
| 5 | CSRF protection | CSRF tokens active? |
| 6 | Auth/authz | Proper authentication and authorization checks? |
| 7 | Rate limiting | All endpoints rate-limited? |
| 8 | Error messages | No sensitive info exposed? |

## Secret Management

```typescript
// NEVER: hardcode
const apiKey = "sk-xxx"

// ALWAYS: environment variables
const apiKey = process.env.OPENAI_API_KEY
if (!apiKey) throw new Error('OPENAI_API_KEY not configured')
```

## Vulnerability Discovery Protocol

```
1. Stop work immediately
2. Delegate to Codex security-analyst
3. CRITICAL: block progress until fixed
4. Rotate leaked credentials
5. Scan entire codebase for similar vulnerabilities
```

## OWASP Top 10

| Vulnerability | Mitigation |
|--------------|------------|
| A01 Broken Access Control | RBAC, authorization checks |
| A02 Cryptographic Failures | Encryption, HTTPS required |
| A03 Injection | Parameterized queries, input validation |
| A04 Insecure Design | Threat modeling |
| A05 Security Misconfiguration | Least privilege principle |
| A06 Vulnerable Components | Dependency auditing |
| A07 Authentication Failures | MFA, session management |
| A08 Software Integrity | Signature verification |
| A09 Logging Failures | Structured logging |
| A10 SSRF | URL validation, allowlists |

## Prohibitions

- Storing credentials in plaintext
- Using `eval()`
- Using unvalidated external input
- Direct production DB access
- Modifying auth features without security review
