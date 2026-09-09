# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-09-09

### Added
- Durable progress ledger (`harness ledger start|append|show|rulings`), stored beside execution receipts under the repository's Git common directory and keyed by the same run ID. It is the run's memory across a compacted context, and it holds the free-form narrative that the closed receipt schema cannot carry.
- Bounded review loop in `/harness-implement`: Minor findings never enter the loop, Critical and Important ones do for at most three rounds, and at the cap every open finding is adjudicated as parked-with-ruling or load-bearing. A load-bearing finding ends the run `blocked` instead of reporting success over a known defect.
- Finding severity classification (Critical, Important, Minor) in `/harness-review`, which the bounded loop consumes.
- Upstream Drift Audit in `docs/PROVENANCE.md`, recording the verified upstream head, drift, and method delta for every acknowledged influence, plus the re-verification command.
- Reversible installer transactions (`core/scripts/lib/transaction.sh`). Every mutation is journaled before it is applied, a mid-install failure restores the previous filesystem state automatically, and `./setup --rollback` undoes the last committed installation.
- `test/test_transaction_lib.sh` and `test/test_install_transaction.sh`, covering the journal primitives and end-to-end installation rollback.
- ShellCheck linting (`npm run lint`) over `bin`, `core/scripts`, `install.sh`, and `setup`, wired into CI on both runners alongside the two new suites.

### Changed
- **BREAKING.** Every published skill is namespaced `harness-*` across Gemini, Claude, Codex, and `.agents`. A `1.0.0` invocation of `/tdd`, `/review`, `/spec`, or any other primitive must become `/harness-tdd`, `/harness-review`, `/harness-spec`. Legacy managed aliases are cleaned up on install.
- `install.sh` now runs under `set -Eeo pipefail` and performs every filesystem mutation through the transaction library. A failure while linking the CLI aborts and rolls back the installation instead of warning and continuing.

### Removed
- **BREAKING.** `/ship` is no longer published as a skill. The CLI equivalent `harness ship` is unchanged.
- **BREAKING.** A default installation exposes only `/harness-implement`, `/harness-fix`, and `/harness-investigate` instead of the fourteen standard skills announced in `1.0.0`. The primitives are bundled privately inside those workflows and can still be exposed as standalone skills with `--expert`.

### Fixed
- `harness doctor --fix` aborted with a Bash `local` error instead of restoring a missing `AGENTS.md`.

## [1.0.0] - 2026-08-26

### Added
- Multi-Call CLI Dispatcher (`bin/harness`) with dynamic alias routing (`agh`, `agent-harness`).
- Universal Multi-Harness bridge (`.gemini`, `.claude`, `.codex`, `.cursor`, `.agents`).
- 14 Standard Agent Skills: `/task`, `/bug`, `/tdd`, `/review`, `/spec`, `/doctor`, `/qa`, `/scan`, `/worktree`, `/conflicts`, `/questionnaire`, `/debt`, `/commit`, `/ship`.
- Rule-driven JSON Landmine & Security scanner (`harness scan`).
- Sub-second workspace context extractor (`harness context`).
- Living Delta Specs (Spec-Driven Development / OpenSpec).
- Starter recipes for Python FastAPI, TypeScript Fullstack, and Go Microservices.
- One-line universal installer & verification test suite (`./setup --verify`).
