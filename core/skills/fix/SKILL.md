---
name: harness-fix
description: Fixes a defect through deterministic reproduction, confirmed root cause, regression TDD, fail-closed QA, and review.
argument-hint: "[Issue / failing behavior / error / trace]"
---

# /harness-fix: Root-Cause Bug-Fix Workflow

Use this workflow when observed behavior violates an existing expectation. If the request introduces intentional new behavior, use `/harness-implement`. If the user wants diagnosis without a code change, use `/harness-investigate`.

## Workflow Contract

- The private `references/bug.md` protocol owns the diagnostic lifecycle; `references/tdd.md` provides the persistent regression proof inside it.
- Production edits are forbidden until a deterministic reproduction and a causal root-cause statement exist.
- A plausible explanation is not a confirmed cause. Evidence must falsify the competing hypotheses that matter.
- The final diff must be the smallest change that breaks the demonstrated causal chain.

### Execution Receipt and Progress Ledger

At workflow start, record the run, retain the returned ID, and open its ledger:

`RUN_ID="$(harness receipt start fix --issue <issue-token>)"`
`harness ledger start "$RUN_ID"`

Omit `--issue` when unavailable. Record phase outcomes with allowlisted tokens such as `harness receipt phase "$RUN_ID" root-cause passed`. The receipt is a closed schema, so anything that needs words belongs in the ledger instead: `harness ledger append "$RUN_ID" phase "root cause confirmed — truncation is the redirection on line 173"`. Finish with `harness receipt finish "$RUN_ID" completed`, or the matching `failed`, `blocked`, or `cancelled` outcome. A receipt or ledger failure must be reported but must never relax the root-cause, regression, QA, or review gates.

The ledger is the run's memory. A compacted context or a resumed session recovers its position from `harness ledger show "$RUN_ID"` and the Git history, never from recollection. A diagnosis is the most expensive thing a fix produces and the easiest thing to lose.

## Phases

1. **Reproduce** — Load `references/bug.md` and establish one deterministic RED command that exhibits the exact defect.
2. **Minimize and diagnose** — Continue `references/bug.md`: reduce the reproduction, inspect the execution path and relevant history, then rank falsifiable hypotheses.
3. **Confirm root cause** — Use the targeted evidence required by `references/bug.md`. State the causal chain from input or state to incorrect output and identify the evidence that proves it.
4. **Regression RED** — Load `references/tdd.md` at the load-bearing seam. Preserve the minimized reproduction as an automated regression test and verify that it fails for the confirmed cause.
5. **Surgical GREEN** — Complete the fix through `references/bug.md` and `references/tdd.md`; change the root-cause layer, verify GREEN, and remove every temporary debug probe.
6. **Validate** — Apply `references/qa.md`; all required gates must pass without suppressed failures.
7. **Review and hand off** — Apply `references/review.md`, then run the Bounded Review Loop below until it exits. Report the cause, regression test, fix, blast radius, verification evidence, and working-tree location.

## Bounded Review Loop

Phase 7 never loops without a bound, and never ends by quietly dropping a finding. The rules
live in `references/loop.md`: load it before the first round and follow it exactly. It owns
the cap, the signature, the adjudication and the rulings, and this workflow does not restate
any of them.

One round here is one correction plus one re-review scoped to the amended code, and the round
label the protocol asks for is `round <R>/3`. `references/review.md` classifies findings
Critical, Important and Minor precisely so this loop can consume them.

## Safety Boundary

- Do not change production code before the root-cause gate in phase 3 passes.
- Do not broaden the fix into cleanup or redesign; record unrelated findings separately.
- Do not leave temporary instrumentation or `[DEBUG-xxxx]` probes in the final diff.
- Do not commit, push, open a pull request, or change external systems unless the user explicitly asks.
- Do not report completion while a load-bearing finding is open. Finish the receipt as `blocked` and hand the decision to the user.

## State Anchor

Report progress on every turn as:

`[FIX: Phase X/7 — <phase> | Root cause: UNPROVEN|CONFIRMED | Next: <next phase>]`

Inside the bounded review loop:

`[FIX: Phase 7/7 — review | Round <R>/3 | Sig: <signature or none> | Open: <C> Critical, <I> Important | Next: <next action>]`

Completion requires:

`[FIX: COMPLETE | Root cause: CONFIRMED | Regression: PASS | QA: PASS | REVIEW: PASS | Rulings: <N>]`

A load-bearing finding at the cap ends the run as:

`[FIX: BLOCKED | Load-bearing findings: <N> | Rulings: <N>]`
