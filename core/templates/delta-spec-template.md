# Delta Spec: {{ISSUE_KEY}} — {{SLUG}}

## 1. Intent & Context
- **Issue / Ticket:** {{ISSUE_KEY}}
- **Summary:** [Brief 2-3 sentence overview of why this change is needed]
- **Target Module / Layer:** [Paths to files and modules affected]

## 2. Requirements & Domain Floor Invariants
- [ ] Requirement 1: ...
- [ ] Requirement 2: ...
- [ ] Invariant: Must not violate `rules/floor.md`

## 3. Implementation Plan
1. [ ] Create test case covering expected behavior (`stack tdd`)
2. [ ] Implement core logic at the appropriate seam
3. [ ] Run `stack scan` and `stack qa all`

## 4. Verification & QA
- **Automated Test Command:** `stack qa test <path>`
- **Expected Outcome:** Green test suite with zero regressions
