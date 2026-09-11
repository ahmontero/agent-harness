# Delta Spec: AH-13 — scan-gate-fail-open

## 1. Intent & Context
- **Issue / Ticket:** AH-13
- **Module:** scanner
- **Summary:** The landmine scanner reports a passing scan in three situations where it verified nothing. `harness qa all` runs the scanner in `--diff` mode, which reads the working tree against `HEAD`, so a secret committed on a feature branch is invisible at exactly the moment the gate matters: a clean tree before `harness ship`. A `--rules` path or a configured `rules.scanner` that does not resolve is replaced by the built-in template instead of refusing, so a project whose rule file was renamed is scanned by rules nobody wrote and told it passed. And `scan`, `context`, and `doctor` discard unrecognised options, so `harness scan --al` scans the empty staged set and exits `0`. All three are the AH-9 shape the rest of the harness has already closed: a check that could not run must never read as a check that passed.
- **Target Module / Layer:** `core/scripts/stack-scan.sh`, `core/scripts/stack-qa.sh`, `core/scripts/stack-context.sh`, `core/scripts/stack-doctor.sh`, `bin/harness`, `core/scripts/stack-completion.sh`, `test/test_cli.sh`, `README.md`, `CHANGELOG.md`, `package.json`.

## 2. Requirements & Domain Floor Invariants
- [x] Requirement 1: The scanner gains a `--branch` mode that scans everything the current branch changes against its merge base with the trunk, committed work included, with `--base <ref>` to name the base explicitly for shallow CI clones.
- [x] Requirement 2: `harness qa all` runs the scanner in `--branch` mode, so a finding committed on the branch fails the aggregate suite.
- [x] Requirement 3: A range the scanner cannot resolve exits `2` — the gate-unrunnable status `stack-qa.sh` already reports as "could not run" — never `0`.
- [x] Requirement 4: A `--rules` argument or a configured `rules.scanner` that does not resolve to a file aborts the scan. The built-in template is a default for a project that asked for nothing, never a substitute for rules that were requested and are missing.
- [x] Requirement 5: `scan`, `context`, and `doctor` reject unrecognised options instead of discarding them, as `debt`, `sync`, `config`, and `worktree remove` already do.
- [x] Invariant: Must not violate `rules/floor.md`. Every new refusal fails closed, and no gate reports success for work it did not read.

## 3. Implementation Plan
1. [x] Add failing coverage to `test/test_cli.sh`: a secret committed on a feature branch with a clean tree must fail `harness qa all`; an unresolvable base must exit `2`; a missing rules file must abort; an unknown option must be refused by all three commands.
2. [x] Implement `--branch` and `--base` in `core/scripts/stack-scan.sh`, resolving the base through `get_trunk_branch` and `git merge-base`, and exiting `2` when no base can be determined.
3. [x] Switch the `scan` gate in `core/scripts/stack-qa.sh` from `--diff` to `--branch`.
4. [x] Make an unresolvable rules path abort, and reject unknown options in `stack-scan.sh`, `stack-context.sh`, and `stack-doctor.sh`.
5. [x] Run `harness qa all` and the full suite.

## 4. Verification & QA
- **Automated Test Command:** `env -u STACK_PROFILE npm test`
- **Expected Outcome:** Green suite with zero regressions, including the four new assertions in groups 33 and 34, and a `harness qa all` on this repository whose scan gate reads the branch rather than the working tree.
