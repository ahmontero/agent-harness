---
name: qa
description: Runs test suites, TDD test loops, linters, type checkers, and static scans for the active project profile.
argument-hint: "test | tdd <path> | lint | types | scan | all"
---

# /qa: Test Suite & Quality Assurance

Executes configured test runners (pytest, vitest, jest, cargo, go) and static linters:

```bash
harness qa test [path]       # Run full or targeted test suite
harness qa tdd <test_path>   # Run single test in fast feedback mode
harness qa lint              # Run project linter (ruff, eslint, etc.)
harness qa types             # Run type checker (mypy, tsc, etc.)
harness qa all               # Run full pipeline (Scan + Lint + Types + Tests)
```
