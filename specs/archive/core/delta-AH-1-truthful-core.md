# Delta Spec: AH-1 — truthful-core

## 1. Intent & Context
- **Issue / Ticket:** AH-1
- **Summary:** Make the harness report quality truthfully before adding composite agent workflows. Quality aggregation must fail when a required check fails, spec verification must validate real content, and this repository must dogfood the rule files it requires from consumers.
- **Target Module / Layer:** `core/scripts/stack-qa.sh`, `core/scripts/stack-spec.sh`, `test/test_cli.sh`, and repository-level `rules/` documentation.

## 2. Requirements & Domain Floor Invariants
- [x] `harness qa all` returns non-zero if scan, lint, type-check, or tests fail, while still reporting which gate failed.
- [x] `harness spec verify <path>` rejects missing, structurally incomplete, or placeholder-filled specs and accepts a complete delta spec.
- [x] The documented `harness spec archive <module> [path]` command moves a verified spec into a module archive and rejects unsafe module names.
- [x] Every scanner test must assert the expected exit status; tests may not convert an unexpected failure into a pass.
- [x] The repository contains `rules/floor.md` and `rules/landmines.md` matching the policy referenced by `AGENTS.md` and scanner documentation.
- [x] Default initialization without a recipe installs every rule file required by the generated `AGENTS.md` and leaves no dangling scanner documentation links.
- [x] Existing successful CLI, recipe initialization, and cross-platform shell behavior remain green.
- [x] Invariant: no gate may claim success after suppressing a required check failure.

## 3. Implementation Plan
1. [x] Add isolated CLI tests proving aggregate QA propagates failures and continues through all configured gates.
2. [x] Add spec fixtures/tests for valid, missing, incomplete, and placeholder-filled delta specs.
3. [x] Implement fail-closed QA aggregation, structural spec verification, and verified spec archiving.
4. [x] Add the repository's canonical floor and landmine documentation.
5. [x] Add and verify generic rule templates for initialization without a recipe.
6. [x] Run landmine scan, syntax checks, and the complete test suite.

## 4. Verification & QA
- **Automated Test Command:** `bash test/test_cli.sh`
- **Expected Outcome:** Negative-path assertions observe non-zero statuses; the full suite and static scan pass with no suppressed failures.

## 5. Non-Goals
- Add the future `implement`, `fix`, or `investigate` composite workflows.
- Add an agent-runtime adapter or execute LLM tool calls from the shell CLI.
- Redesign profile configuration or replace the zero-dependency shell architecture.
