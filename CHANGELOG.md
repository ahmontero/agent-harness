# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Complementary Tooling section in `docs/PROVENANCE.md`, recording `mksglu/context-mode` as a tool that runs alongside `agent-harness` without being invoked by it, and a fifth relationship term for that case. Its Elastic-2.0 license is noted as the standing constraint on borrowing source into this MIT-licensed repository.

## [2.4.0] - 2026-09-11

### Added
- Every installed skill surface now records what it is. `.agent-harness-surface.json` carries the schema, namespace, harness version, installed mode, runtime, and one entry per skill — a `bundle` with a digest of its source content, or a `symlink` without one, because a symlinked expert primitive follows the source and cannot go stale. The digest prefixes every file with its relative path, so a reference republished under a new name signs differently from the original.
- `harness sync --check` reports each identified surface as current, drifted, or unmanaged, with a reason per drifted surface, and exits non-zero if any is stale. It mutates nothing, so it is usable from CI and from a read-only workflow.
- `harness doctor` reports the same surface states. Drift is a warning and doctor still exits `0`, because a stale surface works — it is out of date, not broken. `harness doctor --fix` synchronizes what it found. A check that cannot run reports as unavailable, never as clean.
- `core/scripts/lib/surface.sh`, shared by the installer, sync, and doctor, so that "what should this surface contain?" has one implementation rather than two that can disagree.

### Fixed
- `harness sync` reached only the global surfaces, so a repository initialized with `harness init` kept the skills it was installed with forever. It now synchronizes the current repository's surfaces as well, with `--target <path>` and `--global` to narrow the scope.
- `harness sync` silently downgraded an expert installation to curated. It removed every managed primitive and, never having been passed `--expert`, reinstalled none: a 19-skill expert surface became a 4-skill curated one with nothing said. Synchronization now preserves the mode recorded in the manifest.
- The installer reported success after refusing to write a published skill name occupied by a path it does not manage. It now fails and rolls the transaction back, so the alternative to a complete surface is the previous one rather than a partial one.

### Changed
- Compatibility evidence moves to `schemaVersion: 3` and gains a `surfaceManifest` boolean; the matrix asserts the manifest for the scope and mode of each cell.
- The README version badge now tracks `package.json`.

> **Upgrade note.** Every surface installed before this release has no manifest and is reported `drifted` with the reason `no recorded version`. That is accurate rather than alarming: those surfaces really are of unknown provenance, and several were genuinely stale — this repository's own four and all five global ones were still carrying the 2.1.0 `/harness-implement` without the AH-8 stagnation breaker, and `harness-orchestrate` had never been installed anywhere despite shipping in 2.1.0. One `harness sync` clears it.

## [2.3.0] - 2026-09-10

### Fixed
- `./setup --verify` now exits non-zero when a shell script fails `bash -n` or a `SKILL.md` is missing its frontmatter. Both checks previously printed their failures and still ended with `Verification completed successfully!` and exit `0`: `find -exec bash -n {} \;` discards every status, and the frontmatter loop ran inside a `find | while` pipeline subshell. CI ran this as its verification step, and `harness.config.json` runs it as the repository's lint command, so both gates were decorative. One invocation now reports every problem and exits `1` if any were found.
- `harness scan --staged` reads staged content from the Git index instead of the working tree. It resolved staged *paths* correctly and then grepped whatever was on disk, so a violation that was staged and then reverted committed clean, and a violation that existed only on disk blocked a commit that did not contain it. The installed pre-commit hook runs this mode, so the gate was answering a question nobody asked. Staged blobs are materialized once per file, before the rule loop, and removed when the scanner exits. A path staged as an addition and then deleted from disk is no longer skipped. `--diff` and `--all` still read the working tree, which is what they describe.
- `harness scan --install-hook` no longer destroys a pre-existing `pre-commit` hook. It refuses, names the hook, and prints the line to add manually. The generated hook carries a marker, so re-running over agent-harness's own hook stays idempotent. `--force` replaces a foreign hook after copying it to `pre-commit.harness-backup`, and refuses if that backup already exists. The hooks directory is now resolved through `git rev-parse --git-path hooks`, so installation works from a linked worktree.
- A scanner rule whose pattern `grep -E` cannot use now aborts the scan with a non-zero status naming the rule ID. Two checks run: any pattern containing `(?` is refused because it opens a PCRE group construct that ERE does not define, and every remaining pattern is compiled once against empty input. Both are needed, because BSD `grep` rejects a lookahead outright while GNU `grep` compiles it and then matches something nobody wrote — a compile check alone would refuse the same rule on macOS and accept it on Linux. The shipped `PERF-001` was exactly that case: its `(?!\.iterator|\.values|\[)` is a PCRE negative lookahead, and the rule had never produced a finding in this repository or in any project initialized from the template. It is rewritten as an ERE that matches `.objects.all()` only when the call ends the expression, in both `rules/landmines.json` and `core/templates/landmines-template.json`.

### Changed
- The README version badge now tracks `package.json`; it had been pinned at `2.0.0` since the `2.1.0` release.

> **Upgrade note.** The scanner change alters which inputs the gate rejects. A repository whose pre-commit hook was passing because the scan read the working tree may now see it fail, and a project whose ruleset contains a pattern `grep -E` cannot compile will see `harness scan` refuse to run until that pattern is fixed. Both are corrected defects rather than new restrictions, but neither is a silent upgrade.

## [2.2.0] - 2026-09-09

### Added
- Deterministic failure signatures and a stagnation breaker for the bounded review loop. `harness ledger failure <run_id> [label]` reads a verification capture on stdin, records only its 12-character signature, and answers `continue` on exit `0` or `stagnant` on exit `3`; `harness ledger signature` exposes the same normalization on its own. Normalization scrubs ISO-8601 timestamps, absolute directory prefixes, line and column suffixes, and runs of six or more digits, so two failures differing only in that noise sign identically — including two captures of one failure taken from different checkouts.
- `failure` as a ledger kind, and `profiles.<profile>.loop.stagnationThreshold` (default `2`, minimum `2`) in `schema.json`.

### Changed
- Phase 7 of `/harness-implement` now has a second exit. Previously the three-round cap was the only way out, so a loop that failed the same way three times spent its whole budget re-deriving one failure before it could adjudicate. It now signs every failed round and adjudicates as soon as consecutive rounds sign alike. The cap itself is unchanged, and stagnation can only end the loop earlier than the cap, never later.

## [2.1.0] - 2026-09-09

### Added
- `/harness-orchestrate`, a fourth public workflow that executes an approved delta spec's implementation plan one item at a time, dispatching an implementer subagent and then a separate reviewer subagent that sees the diff but never the implementer's reasoning. It requires subagent dispatch and has no degraded single-context mode; where dispatch is unavailable, `/harness-implement` is the equivalent.
- Per-runtime skill gating. `core/skills/catalog.json` carries a `runtimes` map, and `install.sh` installs a gated public workflow only into the runtimes it names. A workflow absent from the map still reaches every runtime. Removal stays unconditional, so a newly gated workflow leaves the disallowed runtimes without a migration step.
- Per-role model selection under `profiles.<profile>.orchestrate.models`, surfaced by `harness context --json` as `orchestrateModels` and defaulting to `sonnet` for the implementer and `opus` for the reviewer.
- `orchestrate` is a valid execution receipt workflow, with the phase tokens `admit`, `dispatch`, `review`, `resolve`, and `close`.

### Changed
- The compatibility matrix verifies the surface each runtime is declared to receive rather than an identical surface everywhere, and asserts that a gated workflow is absent from every other runtime. Its evidence artifact moves to `schemaVersion: 2` and gains a `runtimeGating` boolean.

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
- `harness spec status` listed archived specs as active. Its `find` recursed into `specs/archive/` and matched directories, unlike `resolve_spec_path`, which was already scoped with `-maxdepth 1 -type f`. Archiving a spec now removes it from the active listing.
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
