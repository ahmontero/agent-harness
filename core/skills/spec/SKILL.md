---
name: harness-spec
description: Manages Spec-Driven Development (OpenSpec / Living Delta Specs) lifecycle for features and modules.
argument-hint: "status | create <issue_key> <slug> | verify [path] | archive [module] [path]"
---

# /harness-spec: Spec-Driven Development & Living Delta Specs

Manages the lifecycle of specifications before, during, and after code changes.

```bash
# 1. Check open specs
harness spec status

# 2. Create a new delta spec
harness spec create <issue_key> <slug>

# 3. Verify compliance
harness spec verify specs/delta-<issue_key>-<slug>.md

# 4. Archive it once the work is handed off
harness spec archive
```

A spec is active while its work is in flight and archived the moment the workflow hands off
a reviewed, verified tree. `harness spec archive` reads the module from the spec's own
`**Module:**` line, so it usually takes no arguments; name one when the spec records none.

Leaving a delivered spec in `specs/` is not untidiness. `harness context` counts what is
there and reports it as work in flight, and that count is the first thing every workflow
reads — so a spec nobody archived makes every later run start from a false statement about
the repository.

---

## 🛑 Anti-Rationalization Gate (Banned LLM Excuses)

| Agent Rationalization (Excuse) | Mandatory Rule / Rebuttal |
| :--- | :--- |
| *"I will write the code first to see how it looks, then generate the spec."* | **BANNED.** Specs establish boundaries and non-goals *before* writing code. |
| *"The task is too simple for a delta spec."* | **BANNED.** Any architectural change, new endpoint, or schema mutation requires a spec. |
| *"I don't need to specify non-goals or edge cases."* | **BANNED.** Explicit non-goals prevent agent scope creep and unintended side-effects. |
| *"The spec can stay in specs/, someone will tidy it later."* | **BANNED.** An active spec is a claim that its work is in flight. Archive it at hand-off, in the same breath as the summary. |

---

## 📍 State Anchor Format
When executing `/harness-spec`, report progress using:
`[SPEC: Status -> Drafting delta spec specs/delta-<key>-<slug>.md]`
`[SPEC: Verified -> All acceptance criteria mapped to tests]`
