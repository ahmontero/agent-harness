# Project Landmines

The executable rules are defined in `rules/landmines.json`. Extend this document with project-specific failure patterns and remediation guidance.

## Security

- Do not commit API keys, tokens, or secrets. Use environment variables or the platform's secret store.
- Do not interpolate untrusted values into SQL. Use parameterized queries supported by the database driver.

## Performance

- Do not materialize unbounded database queries in memory. Use pagination, limits, streaming iterators, or deliberately constrained projections.

## Adding a landmine

1. Add a narrow scanner rule with a stable ID and actionable message.
2. Add one fixture that must fail and one nearby safe fixture that must pass.
3. Point `docLink` to an existing explanation in this repository.
