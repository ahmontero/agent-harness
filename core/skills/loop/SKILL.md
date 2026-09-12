---
name: harness-loop
description: Bounds a review loop so it terminates without dropping a finding, signing each failed round and adjudicating whatever is still open at the cap.
argument-hint: "[Run ID]"
---

# /harness-loop: Bounded Review Loop

A review phase that can repeat needs a bound, or it ends when the agent gets tired of it — and an agent that decides on its own when to stop reviewing never has to say what it decided. This protocol is that bound. It is loaded by every workflow with a review phase and is not restated by any of them, because two statements of one protocol drift: the copy that fell twelve lines behind lost its stagnation breaker, and nothing reported it.

`$RUN_ID` below is the run's identifier, opened by the calling workflow with `harness receipt start` and `harness ledger start`.

## The Loop

- **Minor findings never enter the loop.** Record each one with `harness ledger append "$RUN_ID" deferred "<one-liner>"` and report them at hand-off. They are not dropped; they are not iterated on either.
- **Critical and Important findings enter the loop.** One round is one correction plus one re-review scoped to the amended code. Where the workflow dispatches, that is one implementer dispatch and one reviewer dispatch — never one context doing both, because a reviewer that saw the implementation reasoning is not a reviewer. After each round, record `harness ledger append "$RUN_ID" phase "<round label> (<X> addressed, <Y> open)"`.
- **Three rounds is the cap.** Do not open a fourth. A loop that survives three rounds has a structural problem that another round will not solve.
- **Every failed round is signed before the next one opens.** Pipe the round's verification output through `harness ledger failure "$RUN_ID" "<round label>"`. It records the failure's signature — never the output itself — and answers `continue` on exit `0` or `stagnant` on exit `3`.
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
| *"This review found nothing, so there is nothing to record."* | **BANNED.** A round that found nothing is a round that ended the loop, and the hand-off says so. An empty `harness ledger rulings` is an answer; silence is not. |
