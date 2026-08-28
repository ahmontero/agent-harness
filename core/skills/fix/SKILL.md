---
name: fix
description: Fixes a defect through deterministic reproduction, confirmed root cause, regression TDD, fail-closed QA, and review.
argument-hint: "[Issue / failing behavior / error / trace]"
---

# /fix: Root-Cause Bug-Fix Workflow

Use this workflow when observed behavior violates an existing expectation. If the request introduces intentional new behavior, use `/implement`. If the user wants diagnosis without a code change, use `/investigate`.

## Workflow Contract

- The private `references/bug.md` protocol owns the diagnostic lifecycle; `references/tdd.md` provides the persistent regression proof inside it.
- Production edits are forbidden until a deterministic reproduction and a causal root-cause statement exist.
- A plausible explanation is not a confirmed cause. Evidence must falsify the competing hypotheses that matter.
- The final diff must be the smallest change that breaks the demonstrated causal chain.

### Execution Receipt

At workflow start, record the run and retain the returned ID:

`RUN_ID="$(harness receipt start fix --issue <issue-token>)"`

Omit `--issue` when unavailable. Record phase outcomes with allowlisted tokens such as `harness receipt phase "$RUN_ID" root-cause passed`. Finish with `harness receipt finish "$RUN_ID" completed`, or the matching `failed`, `blocked`, or `cancelled` outcome. A receipt failure must be reported but must never relax the root-cause, regression, QA, or review gates.

## Phases

1. **Reproduce** — Load `references/bug.md` and establish one deterministic RED command that exhibits the exact defect.
2. **Minimize and diagnose** — Continue `references/bug.md`: reduce the reproduction, inspect the execution path and relevant history, then rank falsifiable hypotheses.
3. **Confirm root cause** — Use the targeted evidence required by `references/bug.md`. State the causal chain from input or state to incorrect output and identify the evidence that proves it.
4. **Regression RED** — Load `references/tdd.md` at the load-bearing seam. Preserve the minimized reproduction as an automated regression test and verify that it fails for the confirmed cause.
5. **Surgical GREEN** — Complete the fix through `references/bug.md` and `references/tdd.md`; change the root-cause layer, verify GREEN, and remove every temporary debug probe.
6. **Validate** — Apply `references/qa.md`; all required gates must pass without suppressed failures.
7. **Review and hand off** — Apply `references/review.md`. Report the cause, regression test, fix, blast radius, verification evidence, and working-tree location.

## Safety Boundary

- Do not change production code before the root-cause gate in phase 3 passes.
- Do not broaden the fix into cleanup or redesign; record unrelated findings separately.
- Do not leave temporary instrumentation or `[DEBUG-xxxx]` probes in the final diff.
- Do not commit, push, open a pull request, or change external systems unless the user explicitly asks.

## State Anchor

Report progress on every turn as:

`[FIX: Phase X/7 — <phase> | Root cause: UNPROVEN|CONFIRMED | Next: <next phase>]`

Completion requires:

`[FIX: COMPLETE | Root cause: CONFIRMED | Regression: PASS | QA: PASS | REVIEW: PASS]`
