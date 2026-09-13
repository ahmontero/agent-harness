---
name: harness-investigate
description: Investigates a technical question read-only, gathering evidence and comparing options without implementing a solution.
argument-hint: "[Question / decision / architecture problem]"
---

# /harness-investigate: Evidence-to-Decision Workflow

Use this workflow to understand behavior, compare solutions, evaluate architecture, or prepare a recommendation. It is deliberately read-only and terminates before implementation.

## Workflow Contract

- Separate verified facts, source-backed inferences, assumptions, and unknowns.
- Inspect the current implementation and constraints before proposing alternatives.
- Compare materially distinct options against the same decision criteria.
- Produce a recommendation strong enough for a human to choose `/harness-implement`, `/harness-fix`, further research, or STOP.

### Execution Receipt

The only permitted writes are the private Git receipt and its ledger. Start both with:

`RUN_ID="$(harness receipt start investigate --issue <issue-token>)"`
`harness ledger start "$RUN_ID"`

Omit `--issue` when unavailable. Record phase outcomes without free-form content, for example `harness receipt phase "$RUN_ID" evidence passed`, and put anything that needs words in the ledger: `harness ledger append "$RUN_ID" phase "evidence passed — 17 of 17 commands guard, context does not"`. Finish with `harness receipt finish "$RUN_ID" completed`, or the matching `failed`, `blocked`, or `cancelled` outcome. If receipt or ledger recording fails, disclose the observability gap and keep the investigation itself read-only.

The ledger is the run's memory, and an investigation is the workflow most likely to outlive its own context. A resumed run recovers what it has already established from `harness ledger show "$RUN_ID"` rather than gathering the same evidence twice. This workflow has no bounded review loop: it is read-only and produces a recommendation, so there is no correction to re-review and nothing to adjudicate.

## Phases

1. **Frame the question** — State the decision to be made, scope, success criteria, and relevant unknowns. Load `references/interview.md` only if a missing answer changes the analysis materially.
2. **Gather evidence** — Run `harness context`; inspect architecture, code paths, rules, specs, history, and authoritative external sources when needed.
3. **Establish constraints** — Identify compatibility, operational, security, performance, delivery, and policy constraints supported by evidence.
4. **Develop options** — Present at least two materially different options when alternatives exist, including the status quo when it is viable.
5. **Compare trade-offs** — Evaluate every option using the same criteria, risks, reversibility, dependencies, and validation needs.
6. **Recommend and STOP** — Recommend one option, explain why, list open questions and a proposed implementation outline, then stop for a human decision.

## Safety Boundary

- Apart from its private execution receipt and ledger, this workflow is read-only: do not edit working-tree files, create specs or worktrees, install dependencies, mutate external systems, or run destructive commands.
- Do not silently transition into `/harness-implement` or `/harness-fix` after finding an answer.
- Do not commit, push, or open a pull request.
- If the user explicitly requests implementation during the investigation, finish the current evidence summary and start the appropriate workflow as a distinct phase of work.

## State Anchor

Report progress on every turn as:

`[INVESTIGATE: Phase X/6 — <phase> | Evidence: <verified/pending> | Next: <next phase>]`

Completion requires:

`[INVESTIGATE: COMPLETE | Recommendation: <option> | Implementation: NOT STARTED | STOP]`
