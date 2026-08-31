---
name: harness-tdd
description: Executes a strict Test-Driven Development (TDD) cycle (Red-Green-Refactor) before writing production implementation.
argument-hint: "<test_file_path>"
---

# /harness-tdd: Strict Red-Green-Refactor Loop

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

---

## 🛑 Anti-Rationalization Gate (Banned LLM Excuses)

| Agent Rationalization (Excuse) | Mandatory Rule / Rebuttal |
| :--- | :--- |
| *"This change is trivial/one-line, no test needed."* | **BANNED.** If behavior changes or a bug is fixed, an automated test must prove it. |
| *"I will test manually with curl/console instead."* | **BANNED.** Manual verification evaporates. All verification must be codifed in a test suite. |
| *"I'll write the implementation first, then the test."* | **BANNED.** Writing code before a red test violates TDD and risks false-positive passing tests. |
| *"Mocking the whole subsystem is faster."* | **BANNED.** Over-mocking tests the mock, not the code. Test at the actual integration or unit seam. |

---

## 📍 State Anchor Format
When executing `/harness-tdd`, report progress using:
`[TDD: RED -> Failing test verified at <path>]`
`[TDD: GREEN -> Minimal implementation passing (<duration>)]`
`[TDD: REFACTOR -> Lint & Types verified cleanly]`
