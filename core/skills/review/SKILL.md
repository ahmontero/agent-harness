---
name: harness-review
description: Two-axis code review (Quality Floor & Landmines vs Spec Conformance) before submitting changes.
argument-hint: "[Diff / Commit Range]"
---

# /harness-review: Two-Axis Code Review

Evaluates code quality along two independent, orthogonal axes:

---

## 📐 Axis 1: Standards, Quality Floor & Landmines
- **Quality Floor:** Does the code satisfy `rules/floor.md` invariants?
- **Domain Landmines:** Does the code violate any anti-patterns in `rules/landmines.md`?
- **Static Landmine Scan:** Run `harness scan --branch`. Review happens after the work is committed, and `--diff` reads only what is not committed yet, so on the branch you are reviewing it selects nothing and passes.

## 🎯 Axis 2: Requirement & Spec Conformance
- **Spec Compliance:** Does the implementation match the Delta Spec in `specs/delta-*.md`?
- **Edge Cases:** Are boundary conditions, nullables, and error handling tested?
- **No Scope Creep:** Were unrelated files or speculative abstractions introduced?

---

## 🧮 Finding Severity

Every finding carries exactly one severity, because the bounded review loop in `/harness-implement` consumes it. A review that reports findings without severities is incomplete.

- **Critical** — incorrect behavior, data loss, a security hole, or a violated `rules/floor.md` invariant.
- **Important** — a spec gap, a missing edge-case or error-path test, a `rules/landmines.md` violation, or scope creep.
- **Minor** — naming, comments, or style with no behavioral consequence.

Critical and Important findings enter the fix loop. Minor findings never do; they are recorded and reported at hand-off.

---

## 🛑 Anti-Rationalization Gate (Banned LLM Excuses)

| Agent Rationalization (Excuse) | Mandatory Rule / Rebuttal |
| :--- | :--- |
| *"The diff is small, no need to run static scan."* | **BANNED.** Always run `harness scan --branch` to catch regex/AST landmines. |
| *"The scan passed, so the branch is clean."* | **BANNED** when the mode was not `--branch`. A scan is a claim about the files it read; `--diff` and `--staged` read nothing on a committed branch and say so. Read the mode in the output before believing the verdict. |
| *"These extra abstractions are good for future-proofing."* | **BANNED.** Unrequested abstractions are scope creep. Keep modules deep and minimal. |
| *"Edge cases can be handled in a follow-up PR."* | **BANNED.** Code is not complete until boundary conditions and error paths are tested. |
| *"I'll grade this Minor so the fix loop can end."* | **BANNED.** Severity describes the defect, not your appetite for another round. Grade the finding, then adjudicate it at the cap. |

---

## 📍 State Anchor Format
When executing `/harness-review`, report results using:
`[REVIEW: Axis 1 (Standards & Landmines) -> PASS/FAIL | Axis 2 (Spec Conformance) -> PASS/FAIL | Findings: <C> Critical, <I> Important, <M> Minor]`
