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

## Upstream Drift Audit

The snapshots above record the upstream state from which each influence was drawn; they are deliberately not bumped when upstream moves. This section records the most recent verification of upstream drift so that a future contributor knows what has changed since the influence was taken, and whether re-derivation is warranted.

**Last verified: 2026-09-09**

| Upstream project | Snapshot in table | Upstream head at verification | Drift | Method delta relevant to `agent-harness` |
| :--- | :--- | :--- | :--- | :--- |
| addyosmani/agent-skills | `f63ec56` | [`6ca0cd7`](https://github.com/addyosmani/agent-skills/tree/6ca0cd7db39b41b1c37e26d335c507ee92382c6d) (`v0.6.9`) | 48 commits ahead | Yes — new `constraint-driven-development` skill (written quality bar, suppression/skipped-test drift detection); `context-engineering` substantially expanded; `planning-and-task-breakdown` extended. Candidate for re-derivation into `rules/floor.md` and `scan`. |
| obra/superpowers | `b36e082` | [`b36e082`](https://github.com/obra/superpowers/tree/b36e0829c6d0140e93cfef2ca599b1b07d4a7797) (`v6.3.0`) | None — identical | No. Snapshot is current upstream head. |
| mattpocock/skills | `6654f6b` | [`3cca18b`](https://github.com/mattpocock/skills/tree/3cca18b368ae95cdbdebbff572ccafa662551015) | 2 commits ahead | No. `CLAUDE.md` and `scripts/link-skills.sh` only; `diagnosing-bugs/SKILL.md` is unchanged. |
| Fission-AI/OpenSpec | `a0ddb60` | [`e062b95`](https://github.com/Fission-AI/OpenSpec/tree/e062b9572be933564ba3899d059377dfa1393e32) (`v1.12.0`) | 20 commits ahead | Yes — `validate --report findings`, `show --diff` for delta requirements, and explore/propose guidance that inspects code before drafting. Candidate for re-derivation into `spec/SKILL.md`. |
| ayghri/i-have-adhd | `cbe69fb` | [`24d22f7`](https://github.com/ayghri/i-have-adhd/tree/24d22f783e57cb73c957848b588c6f651b6f9cd8) | 25 commits ahead | No. README translations, install docs, and eval harness only; the communication rules themselves are unchanged. |

Re-verification command (requires `gh`):

```bash
gh api "repos/<owner>/<repo>/compare/<snapshot-sha>...main" --jq '"ahead_by=\(.ahead_by) status=\(.status)"'
```

A re-derived influence updates the snapshot column in the table above **and** the local evidence links, because the snapshot must always name the upstream state that the local implementation was actually derived from.

## First-Party Lineage

Some mechanisms are carried over from the author's own private `easys-stack` toolkit rather than from an external project. These are recorded here because the licensing policy below requires provenance language to match the actual reuse, and because a reader comparing the two codebases should not have to guess.

| Origin | Relationship | Reuse in `agent-harness` | Local evidence |
| :--- | :--- | :--- | :--- |
| `easys-stack` (private, same author) | Ported and renamed | Reversible installer transactions: the journal layout, the `ERR`-trap rollback, and the mutation primitives were ported with the environment prefix renamed to `HARNESS_*`. `transaction_remove_tree` is new here, because this installer removes managed skill directories, and the primitives were hardened to fail closed instead of writing through a path they could not remove. | [`transaction.sh`](../core/scripts/lib/transaction.sh), [`test_transaction_lib.sh`](../test/test_transaction_lib.sh), [`test_install_transaction.sh`](../test/test_install_transaction.sh) |

`easys-stack` is not public, is not a dependency, and shares this project's authorship, so the port creates no third-party license obligation and adds no entry to `THIRD_PARTY_NOTICES.md`. The two test suites were rewritten against this installer's own flags rather than ported line for line; the upstream cases for `--plan`, `--check`, collision fail-closed semantics, and completion blocks describe an installer contract `agent-harness` does not have.

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
