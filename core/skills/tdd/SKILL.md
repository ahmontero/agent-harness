---
name: tdd
description: Executes a strict Test-Driven Development (TDD) cycle (Red-Green-Refactor) before writing production implementation.
argument-hint: "<test_file_path>"
---

# /tdd: Strict Red-Green-Refactor Loop

Enforces the classic Kent Beck / Martin Fowler TDD discipline. Never write production code without a failing test first.

---

## 🔁 The TDD Cycle

1. **RED: Write the Minimal Failing Test**:
   - Write a unit/integration test describing the desired behavior.
   - Run: `harness tdd <test_file_path>`
   - Verify that the test fails **for the expected reason**.

2. **GREEN: Write Minimal Implementation**:
   - Write the simplest code that makes the test pass.
   - Run: `harness tdd <test_file_path>`
   - Verify that the test passes (GREEN).

3. **REFACTOR: Clean Code & Architecture**:
   - Remove duplication, improve naming, ensure domain floor compliance.
   - Run `harness qa lint` and `harness qa types`.
   - Ensure tests remain GREEN throughout refactoring.
