---
name: harness-implement
description: Implements a new feature or behavior change by composing discovery, isolation, specification, TDD, simplification, QA, and review.
argument-hint: "[Issue / requirement / acceptance criteria]"
---

# /harness-implement: Feature Delivery Workflow

Use this workflow for new behavior, enhancements, and intentional changes. If the request is primarily a defect with existing behavior, use `/harness-fix`. If the requested outcome is analysis or options only, use `/harness-investigate`.

## Workflow Contract

- Start from explicit acceptance criteria and identify the smallest observable behavior change.
- Load the private protocols named in each phase from `references/`; do not restate, weaken, or bypass their gates.
- Advance only when the current phase has produced its required evidence.
- Finish with a reviewed, verified working tree. Publication is a separate, explicitly authorized action.

### Execution Receipt and Progress Ledger

At workflow start, record the run, retain the returned ID, and open its ledger:

`RUN_ID="$(harness receipt start implement --issue <issue-token>)"`
`harness ledger start "$RUN_ID"`

Omit `--issue` when no safe issue token exists. After each phase, record only the phase token and lifecycle status, for example `harness receipt phase "$RUN_ID" tdd passed`. The receipt is a closed schema, so anything that needs words belongs in the ledger instead: `harness ledger append "$RUN_ID" phase "tdd passed — 14/14 green"`. Before the final response, call `harness receipt finish "$RUN_ID" completed`; use `failed`, `blocked`, or `cancelled` when appropriate. If receipt or ledger recording fails, report that observability failure and continue enforcing every engineering gate.

The ledger is the run's memory. A compacted context or a resumed session recovers its position from `harness ledger show "$RUN_ID"` and the Git history, never from recollection. Where the two disagree, the ledger is right and your memory is wrong.

## Phases

1. **Understand** — Run `harness context`, inspect applicable rules, and state acceptance criteria, constraints, and non-goals. Load `references/interview.md` only when a missing decision would materially change the implementation.
2. **Scope and isolate** — Load `references/task.md` to identify architectural seams. Follow `references/spec.md` and `references/worktree.md`; significant changes require both before production edits.
3. **RED** — Load `references/tdd.md` and add the smallest failing test for one acceptance criterion. Record the command and expected failure reason.
4. **GREEN** — Continue the protocol in `references/tdd.md` with the minimal production change that makes the targeted test pass.
5. **REFACTOR** — Complete `references/tdd.md`, then apply `references/simplify.md` to the diff. Remove duplication and accidental complexity while keeping tests green.
6. **Validate** — Apply `references/qa.md`. Every required gate must pass; a missing configured gate must be reported, not represented as success.
7. **Review and hand off** — Apply `references/review.md` against the delta spec and quality floor, then run the Bounded Review Loop below until it exits. Archive the delta spec with `harness spec archive`: its work is no longer in flight, and `harness context` counts what is left in `specs/` as work that is. Summarize changed behavior, evidence, remaining risks, and the exact working-tree location.

For multiple acceptance criteria, repeat phases 3–5 in small vertical slices instead of implementing the whole feature before testing.

## Bounded Review Loop

Phase 7 never loops without a bound, and never ends by quietly dropping a finding. The rules
live in `references/loop.md`: load it before the first round and follow it exactly. It owns
the cap, the signature, the adjudication and the rulings, and this workflow does not restate
any of them.

One round here is one fix plus one re-review scoped to the amended code, and the round label
the protocol asks for is `round <R>/3`.

## Safety Boundary

- Do not use this workflow for a bug until the request is reclassified or the user confirms the intent.
- Do not edit production code before the spec/isolation policy is satisfied and a RED test is verified.
- Do not commit, push, open a pull request, or change external systems unless the user explicitly asks.
- Do not absorb unrelated refactors; record them as debt and continue with the active requirement.
- Do not report completion while a load-bearing finding is open. Finish the receipt as `blocked` and hand the decision to the user.

## State Anchor

Report progress on every turn as:

`[IMPLEMENT: Phase X/7 — <phase> | Gate: <evidence or pending> | Next: <next phase>]`

Inside the bounded review loop:

`[IMPLEMENT: Phase 7/7 — review | Round <R>/3 | Sig: <signature or none> | Open: <C> Critical, <I> Important | Next: <next action>]`

Completion requires:

`[IMPLEMENT: COMPLETE | TDD: PASS | QA: PASS | REVIEW: PASS | Rulings: <N> | Publish: NOT REQUESTED|COMPLETE]`

A load-bearing finding at the cap ends the run as:

`[IMPLEMENT: BLOCKED | Load-bearing findings: <N> | Rulings: <N>]`
