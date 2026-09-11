# Delta Spec: AH-2 — composite-workflows

## 1. Intent & Context
- **Issue / Ticket:** AH-2
- **Summary:** Expose three user-intent workflows that compose the existing engineering skills without duplicating their detailed procedures. Each workflow must define when it may edit, the evidence required to advance, and the condition at which it stops.
- **Target Module / Layer:** `core/skills/{implement,fix,investigate}/SKILL.md`, installation validation, and user-facing workflow documentation.

## 2. Requirements & Domain Floor Invariants
- [x] `/implement` orchestrates requirement understanding, impact analysis, optional clarification, spec/worktree policy, TDD, simplification, QA, and review.
- [x] `/fix` requires deterministic reproduction and confirmed root cause before production edits, then regression TDD, QA, and review.
- [x] `/investigate` is read-only, produces evidence/options/trade-offs/recommendation, and stops without implementation.
- [x] None of the workflows may commit, push, open a pull request, or invoke `ship` without an explicit user request.
- [x] Workflow state anchors make the active phase, satisfied gate, and next phase observable.
- [x] Default initialization distributes all three workflows through every supported skill directory.
- [x] Invariant: composite workflows reference primitive skills instead of restating or weakening their protocols.

## 3. Implementation Plan
1. [x] Add contract tests for workflow frontmatter, phases, safety boundaries, and primitive skill references.
2. [x] Add the three composite `SKILL.md` definitions.
3. [x] Verify installation exposes the workflows to `.agents`, Claude, Codex, and Gemini-compatible directories.
4. [x] Update README to present workflows as the primary user surface and individual skills as primitives.
5. [x] Run static scan, spec verification, and the complete test suite.

## 4. Verification & QA
- **Automated Test Command:** `bash test/test_cli.sh`
- **Expected Outcome:** All workflow contracts and runtime links are present; legacy skills and CLI tests remain green.

## 5. Non-Goals
- Add a shell-based LLM runner or vendor-specific agent adapter.
- Automatically classify free-form requests into workflows.
- Add execution receipts, persistence, resume, or workflow statistics.
