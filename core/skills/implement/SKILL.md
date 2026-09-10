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
7. **Review and hand off** — Apply `references/review.md` against the delta spec and quality floor, then run the Bounded Review Loop below until it exits. Summarize changed behavior, evidence, remaining risks, and the exact working-tree location.

For multiple acceptance criteria, repeat phases 3–5 in small vertical slices instead of implementing the whole feature before testing.

## Bounded Review Loop

Phase 7 never loops without a bound, and never ends by quietly dropping a finding.

- **Minor findings never enter the loop.** Record each one with `harness ledger append "$RUN_ID" deferred "<one-liner>"` and report them at hand-off.
- **Critical and Important findings enter the loop.** One round is one fix plus one re-review scoped to the amended code. After each round, record `harness ledger append "$RUN_ID" phase "round <R>/3 (<X> addressed, <Y> open)"`.
- **Three rounds is the cap.** Do not open a fourth. A loop that survives three rounds has a structural problem that another round will not solve.
- **Every failed round is signed before the next one opens.** Pipe the round's verification output through `harness ledger failure "$RUN_ID" "round <R>/3"`. It records the failure's signature — never the output itself — and answers `continue` on exit `0` or `stagnant` on exit `3`.
- **A `stagnant` answer ends the loop now.** Go straight to adjudication with the rounds you have, even when rounds remain under the cap. Two rounds that fail equivalently have already told you the loop is not converging; a third would only cost the budget you need for adjudication.
- **At the cap, adjudicate every open finding individually.** Either park it — `harness ledger append "$RUN_ID" parked "<finding> — Ruling: <why the code stands>"` — or classify it as load-bearing, meaning later work would build on the defect.
- **A load-bearing finding at the cap ends the workflow as blocked.** Record `harness ledger append "$RUN_ID" ruling "<finding> — blocked: <what the user must decide>"`, call `harness receipt finish "$RUN_ID" blocked`, and hand the decision to the user.

Before the final response, run `harness ledger rulings "$RUN_ID"` and reproduce every line it returns, in recorded order. That list is the only place the decisions you took on the user's behalf reach them.

## 🛑 Anti-Rationalization Gate (Banned LLM Excuses)

| Agent Rationalization (Excuse) | Mandatory Rule / Rebuttal |
| :--- | :--- |
| *"One more round and the review will converge."* | **BANNED.** Past three rounds the failure is structural, not incremental. Adjudicate every open finding instead. |
| *"This finding is clearly wrong, I'll drop it."* | **BANNED.** Adjudication happens only at the cap, and every adjudication is a ledger line. Silent discards are forbidden. |
| *"The ledger is bookkeeping overhead."* | **BANNED.** The ledger is what survives compaction. Without it, a resumed run repeats phases that already passed. |
| *"The signature matched, but this failure is really different."* | **BANNED.** The signature already discarded timestamps, paths, line numbers, and IDs. What is left is the failure. If you believe two signed failures differ materially, the normalization is wrong and that is a defect to report, not a licence to open another round. |

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
