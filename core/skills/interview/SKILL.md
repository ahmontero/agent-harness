---
name: harness-interview
description: Interrogates requirements and resolves design ambiguity by asking exactly one structured, multiple-choice question at a time before drafting specs or code.
argument-hint: "[Feature Idea / Ticket / Ambiguity Area]"
---

# /harness-interview: Socratic Requirement Interrogator

Extracts exact user requirements and resolves architectural ambiguity by asking **one clear, structured question at a time** before drafting specs or touching source code.

---

## 🎯 The Interview Protocol

1. **One Question Per Turn**:
   - Never overwhelm the user with a bulleted list of 5 questions.
   - Ask the single most critical, load-bearing question first.

2. **Structured Multiple-Choice Options**:
   - Present 2 to 4 distinct, concrete architectural options.
   - Prefix the best engineering choice with `(Recommended)`.
   - Provide a brief 1-line rationale for the recommendation.

3. **No Redundant Questions**:
   - Inspect existing codebase interfaces, DB schemas, and configurations first before asking questions answerable from code.

4. **Crystallize into Delta Spec**:
   - Once all key ambiguities are resolved, automatically generate the delta spec:
     ```bash
     harness spec create <issue_key> <slug>
     ```

---

## 🛑 Anti-Rationalization Gate (Banned LLM Excuses)

| Agent Rationalization (Excuse) | Mandatory Rule / Rebuttal |
| :--- | :--- |
| *"I'll dump 10 questions at once to get it over with."* | **BANNED.** High cognitive load causes user burnout. Ask exactly 1 question per turn. |
| *"I'll assume the requirements without asking."* | **BANNED.** Unstated assumptions cause architectural churn. Clarify ambiguous boundaries first. |
| *"I don't need to recommend an option."* | **BANNED.** As lead architect, always recommend the cleanest option with a 1-line rationale. |

---

## 📍 State Anchor Format
When executing `/harness-interview`, report state using:
`[INTERVIEW: Question X/Y | Topic: <Boundary/Data Model> | Next: Draft Spec]`
