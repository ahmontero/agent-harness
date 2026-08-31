---
name: harness-spec
description: Manages Spec-Driven Development (OpenSpec / Living Delta Specs) lifecycle for features and modules.
argument-hint: "status | create <issue_key> <slug> | verify [path]"
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
```

---

## 🛑 Anti-Rationalization Gate (Banned LLM Excuses)

| Agent Rationalization (Excuse) | Mandatory Rule / Rebuttal |
| :--- | :--- |
| *"I will write the code first to see how it looks, then generate the spec."* | **BANNED.** Specs establish boundaries and non-goals *before* writing code. |
| *"The task is too simple for a delta spec."* | **BANNED.** Any architectural change, new endpoint, or schema mutation requires a spec. |
| *"I don't need to specify non-goals or edge cases."* | **BANNED.** Explicit non-goals prevent agent scope creep and unintended side-effects. |

---

## 📍 State Anchor Format
When executing `/harness-spec`, report progress using:
`[SPEC: Status -> Drafting delta spec specs/delta-<key>-<slug>.md]`
`[SPEC: Verified -> All acceptance criteria mapped to tests]`
