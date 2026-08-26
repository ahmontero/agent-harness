---
name: review
description: Two-axis code review (Quality Floor & Landmines vs Spec Conformance) before submitting changes.
argument-hint: "[Diff / Commit Range]"
---

# /review: Two-Axis Code Review

Evaluates code quality along two independent, orthogonal axes:

---

## 📐 Axis 1: Standards, Quality Floor & Landmines
- **Quality Floor:** Does the code satisfy `rules/floor.md` invariants?
- **Domain Landmines:** Does the code violate any anti-patterns in `rules/landmines.md`?
- **Static Landmine Scan:** Run `harness scan --diff`.

## 🎯 Axis 2: Requirement & Spec Conformance
- **Spec Compliance:** Does the implementation match the Delta Spec in `specs/delta-*.md`?
- **Edge Cases:** Are boundary conditions, nullables, and error handling tested?
- **No Scope Creep:** Were unrelated files or speculative abstractions introduced?
