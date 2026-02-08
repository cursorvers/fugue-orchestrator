# Testing Rules

## Principle

**Test-Driven Development (TDD) as standard.**

## Coverage Requirements

### New Code (Required)

| Type | Minimum Coverage | Scope |
|------|-----------------|-------|
| General code | 80% | New features |
| Finance/payment | 100% | Stripe, billing, wallets |
| Auth/security | 100% | Authentication, authorization, encryption |

## TDD Workflow

```
1. RED    - Write failing test first
2. FAIL   - Run test, confirm failure
3. GREEN  - Minimal implementation to pass
4. PASS   - Run test, confirm success
5. REFACTOR - Improve code quality
6. COVERAGE - Verify 80%+
```

**Important: Write tests BEFORE implementation (RED-GREEN strictly enforced)**

## Test Types

| Type | Scope | Tools |
|------|-------|-------|
| Unit | Single function, utility, component | Jest, Vitest |
| Integration | API endpoints, DB operations | Supertest |
| E2E | Critical user flows | Playwright |

## On Test Failure

1. **Fix implementation before fixing tests**
   - If test is correct, fix the implementation
   - Only fix test if test has a bug

2. **Verify**
   - Test isolation is proper
   - Mocks are accurate
   - Preconditions are correct

## Emergency Deploy (Break Glass)

**TDD skip allowed for hotfixes only when:**

1. Fixing a production outage
2. Approved by 3-party consensus
3. Tests added within 24 hours post-fix
4. Reason logged

## Prohibitions

- Committing without tests (absolute for finance/auth, except hotfix)
- Mocking with `any` type
- Running E2E tests in production
- Merging new code with <80% coverage
