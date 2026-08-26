---
name: bug
description: Investigates, analyzes root causes, and fixes bugs using a disciplined 6-phase red-capable feedback loop without regressions.
argument-hint: "[Issue Key / ID] [Error / Trace / Sentry Issue]"
---

# /bug: Systematic 6-Phase Debugging Protocol

Combines the rigor of **Superpowers** and the disciplined feedback-loop protocol of **Matt Pocock**. Jumping straight to editing code without an automated failing signal is strictly forbidden.

---

## 🔬 The 6-Phase Debugging Loop

```mermaid
flowchart TD
    P1["Phase 1: Build Tight Feedback Loop<br>Deterministic red-capable command"] --> P2["Phase 2: Reproduce & Minimise<br>Shrink to load-bearing elements"]
    P2 --> P3["Phase 3: Rank Falsifiable Hypotheses<br>3-5 predictions before code changes"]
    P3 --> P4["Phase 4: Targeted Instrumentation<br>Tagged [DEBUG-xxxx] probes"]
    P4 --> P5["Phase 5: Surgical Fix & Regression Test<br>Green loop at correct seam"]
    P5 --> P6["Phase 6: Verification & Cleanup<br>Remove all debug tags, run suite"]
```

### Phase 1: Build a Tight, Red-Capable Feedback Loop
1. Construct **one test command** that:
   - Reproduces the exact error (goes **RED**).
   - Is deterministic and fast (<5s).
2. Execute: `harness tdd <test_path>` and verify RED state.

### Phase 2: Reproduce & Minimise
- Strip unnecessary payload fields or setup fixtures until only the load-bearing elements remain.

### Phase 3: Rank Falsifiable Hypotheses
- List 2-4 explicit hypotheses explaining the root cause.
- Define what evidence would prove or disprove each one.

### Phase 4: Targeted Instrumentation
- Add temporary debug probes tagged `[DEBUG-xxxx]`. Run the red command to inspect variables.

### Phase 5: Surgical Fix & Green Loop
- Apply the minimal fix at the root cause layer (not a surface patch).
- Verify the test turns **GREEN**.

### Phase 6: Verification & Cleanup
- Remove all `[DEBUG-xxxx]` probes.
- Run `harness qa all` to ensure zero regressions.
