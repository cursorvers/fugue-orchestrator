# Coding Style Rules

## Principle

**Immutability first.**

## Immutability (CRITICAL)

```typescript
// NEVER: direct mutation
obj.property = newValue
array.push(item)

// ALWAYS: create new (shallow copy)
const newObj = { ...obj, property: newValue }
const newArray = [...array, item]
```

**Note**: Spread syntax is shallow copy only.
For nested objects use:
- **Immer**: `produce(state, draft => { draft.nested.value = x })`
- **structuredClone**: `structuredClone(obj)` (deep copy)

## File Organization

| Item | Recommended | Maximum | On Exceed |
|------|-------------|---------|-----------|
| File lines | 200-400 | 800 | Must split |
| Function lines | 20-30 | 50 | Must split |
| Nesting depth | 2 | 4 | Early return |

## Naming Conventions

| Type | Rule | Example |
|------|------|---------|
| Variables | camelCase, descriptive | `marketSearchQuery` not `q` |
| Functions | verb-noun | `fetchMarketData`, `validateInput` |
| Constants | UPPER_SNAKE | `MAX_RETRY_COUNT` |
| Components | PascalCase | `UserProfile` |
| Types/Interfaces | PascalCase | `UserData`, `IUserService` |

## Input Validation

```typescript
// ALWAYS: validate with Zod
import { z } from 'zod'

const UserSchema = z.object({
  email: z.string().email(),
  age: z.number().min(0).max(150)
})

const validated = UserSchema.parse(input)
```

## Error Handling

```typescript
// ALWAYS: Try-Catch + informative messages
try {
  await riskyOperation()
} catch (error) {
  logger.error('Operation failed', { error, context })
  throw new AppError('User-friendly message', { cause: error })
}
```

## Code Smell Detection

| Issue | Warning |
|-------|---------|
| Function > 50 lines | Consider splitting |
| File > 800 lines | Must split |
| Nesting > 4 levels | Convert to early return |
| Magic numbers | Use named constants |
| `any` type | Use specific types |
| console.log | Remove or use logger |
