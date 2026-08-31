---
name: harness-simplify
description: Audits and simplifies recently written code, stripping speculative abstractions, dead code, and unnecessary complexity (YAGNI & Deep Modules).
argument-hint: "[file_path | diff_range]"
---

# /harness-simplify: Code Simplification & Complexity Reducer

Audits code for accidental complexity, speculative abstractions, and over-engineering introduced by AI agents. Follows John Ousterhout's *Philosophy of Software Design* (Deep Modules) and YAGNI (You Aren't Gonna Need It).

---

## 🧹 The Simplification Checklist

1. **Eliminate Shallow Wrappers**:
   - Merge single-use pass-through functions into their callers.
   - Remove 1-method interfaces or classes whose abstraction adds more syntax than value.

2. **Flatten Unnecessary Indirection**:
   - Replace complex callback chains or dynamic handler factories with simple, direct function calls.
   - Replace speculative generic types with concrete types if only one variant exists.

3. **Purge Dead & Speculative Code**:
   - Delete unused arguments, unread return values, and speculative configuration flags.
   - Ensure every exported function or type is actually consumed and tested.

4. **Verify Observable Behavior**:
   - Run `harness qa tdd <test_path>` or `harness qa test` before and after simplification.
   - Behavior and public contracts must remain 100% GREEN.

---

## 🛑 Anti-Rationalization Gate (Banned LLM Excuses)

| Agent Rationalization (Excuse) | Mandatory Rule / Rebuttal |
| :--- | :--- |
| *"We might need this abstraction for future extensibility."* | **BANNED.** Do not build for hypothetical futures. Build the simplest design that satisfies current specs. |
| *"More files and helper classes make the code more enterprise."* | **BANNED.** Shallow modules increase cognitive load. Prefer deep modules with simple interfaces. |
| *"I don't need to re-run tests after simplifying."* | **BANNED.** Refactoring without re-running tests is reckless. All tests must be re-verified. |

---

## 📍 State Anchor Format
When executing `/harness-simplify`, report progress using:
`[SIMPLIFY: Auditing -> <file_or_diff> | Removed X lines of dead abstraction | Tests GREEN]`
