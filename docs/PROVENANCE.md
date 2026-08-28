# Provenance and Acknowledgements

`agent-harness` combines original integration work with engineering methods learned from the wider open-source community. This document records those influences precisely so that acknowledgement remains useful, auditable, and distinct from dependency declarations.

## Relationship Vocabulary

- **Inspired by** means the project influenced a principle or design direction; no source reuse is implied.
- **Adapted method** means `agent-harness` implements a recognizable workflow or technique in its own structure and language.
- **Uses** is reserved for software that is installed, imported, executed, or redistributed as a dependency.
- **Complies with** means the repository follows an external standard without treating the standard as a dependency.

The commit links below are provenance snapshots, not dependency pins. The listed projects are not installed or executed by `agent-harness` during normal operation.

## Open-Source Influences

| Upstream project | Relationship | Influence in `agent-harness` | Local evidence | Snapshot | License |
| :--- | :--- | :--- | :--- | :--- | :--- |
| [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) | Inspired by; adapted method | Skills expressed as executable workflows, explicit verification gates, and anti-rationalization safeguards. | [`AGENTS-template.md`](../core/templates/AGENTS-template.md), [`tdd/SKILL.md`](../core/skills/tdd/SKILL.md), [`review/SKILL.md`](../core/skills/review/SKILL.md) | [`f63ec56`](https://github.com/addyosmani/agent-skills/tree/f63ec56a3cc936408d792956ae583c3c96a825bd) | MIT |
| [obra/superpowers](https://github.com/obra/superpowers) | Inspired by; adapted method | Red-Green-Refactor discipline, systematic debugging gates, and isolated worktree workflows. | [`tdd/SKILL.md`](../core/skills/tdd/SKILL.md), [`bug/SKILL.md`](../core/skills/bug/SKILL.md), [`worktree/SKILL.md`](../core/skills/worktree/SKILL.md) | [`b36e082`](https://github.com/obra/superpowers/tree/b36e0829c6d0140e93cfef2ca599b1b07d4a7797) | MIT |
| [mattpocock/skills](https://github.com/mattpocock/skills) | Adapted method | Tight red-capable feedback loops, minimized reproductions, ranked falsifiable hypotheses, and tagged temporary probes. | [`bug/SKILL.md`](../core/skills/bug/SKILL.md), [`fix/SKILL.md`](../core/skills/fix/SKILL.md) | [`diagnosing-bugs` at `6654f6b`](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/engineering/diagnosing-bugs/SKILL.md) | MIT |
| [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) | Inspired by; adapted method | Spec-Driven Development, living specifications, delta requirements, verification, and archival lifecycle. | [`spec/SKILL.md`](../core/skills/spec/SKILL.md), [`task/SKILL.md`](../core/skills/task/SKILL.md) | [`a0ddb60`](https://github.com/Fission-AI/OpenSpec/tree/a0ddb60d040c61f4907436a9d91310934b1dda63) | MIT |
| [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd) | Inspired by; adapted method | Action-first communication, concise state anchors, bounded cognitive load, and tangent control. | [`AGENTS-template.md`](../core/templates/AGENTS-template.md) | [`cbe69fb`](https://github.com/ayghri/i-have-adhd/tree/cbe69fb83c08a37cf54d5ec9ec6bb88c8bc9973c) | MIT |

## Standards and Conceptual Foundations

These references shape repository conventions but are not software dependencies:

- [Conventional Commits](https://www.conventionalcommits.org/) defines the commit-message convention used by the project.
- [Keep a Changelog](https://keepachangelog.com/) provides the structure used by `CHANGELOG.md`.
- [Contributor Covenant](https://www.contributor-covenant.org/) is the source acknowledged by `CODE_OF_CONDUCT.md`.
- Kent Beck and Martin Fowler's TDD and refactoring work informs the Red-Green-Refactor discipline.
- John Ousterhout's *A Philosophy of Software Design* informs the deep-module and cognitive-load guidance in [`simplify/SKILL.md`](../core/skills/simplify/SKILL.md).

## Licensing Policy

The table records the upstream license detected at the referenced snapshot. Inspiration and independent reimplementation do not make those projects runtime dependencies.

If a future contribution copies or redistributes a substantial portion of upstream source code or documentation, that contribution must:

1. identify the exact upstream file and commit;
2. verify that the upstream license permits the intended use;
3. preserve all copyright and permission notices required by that license; and
4. add or update `THIRD_PARTY_NOTICES.md` when the license or scope of reuse requires it.

Do not describe a relationship as “inspired by” when source material was copied or closely translated. Provenance language must match the actual reuse.
