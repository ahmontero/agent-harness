# Quality Floor Invariants

Adapt these invariants to the domain, but do not weaken them silently.

1. **Tests prove behavior changes.** Create a deterministic failing test before changing production behavior and keep the regression test after the fix.
2. **Required quality gates fail closed.** A failing scan, linter, type-check, or test suite blocks completion and publication.
3. **Errors remain observable.** Do not swallow failures, replace them with unconditional success, or ask the user to perform verification that can be automated.
4. **Changes remain scoped.** Avoid unrelated refactors and speculative abstractions while implementing an active requirement.
5. **Side effects require intent.** Investigation is read-only; publishing branches, opening pull requests, or changing external systems requires explicit authorization.
6. **Project rules are authoritative.** Add domain-specific invariants and known failure patterns to this directory as they are discovered.
