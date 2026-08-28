# Agent Harness Landmines

The executable scanner configuration lives in `rules/landmines.json`. Every entry must have a stable ID, severity, remediation message, applicable file extensions, and a documentation link that resolves inside this repository.

## Security rules

- **SEC-001 — Hardcoded credentials:** never commit API keys, tokens, or secrets. Read credentials from the runtime environment or the platform's secret store.
- **SEC-002 — Interpolated SQL:** never build SQL by interpolating untrusted values. Use parameterized queries supported by the database driver.

## Performance rules

- **PERF-001 — Unbounded ORM queries:** do not materialize an unrestricted query in memory. Apply a bound, pagination, streaming iterator, or a deliberately constrained projection.

## Adding a rule

1. Add a fixture that should fail and a nearby safe fixture that should pass.
2. Run the scanner against both fixtures and assert their exit statuses.
3. Keep patterns narrow enough to avoid blocking safe code.
4. Document the remediation here and ensure `docLink` points to an existing file.
