# TypeScript Fullstack Quality Floor

1. **Strict Types**: No `any`. Use `unknown`, generics, or strict union types.
2. **Zod Validation**: Validate all network boundaries (API inputs, environment variables, webhooks) with Zod.
3. **Immutable State Updates**: Never mutate state arrays/objects directly in React/Next.js components.
