# Delta Spec: AH-15 — ci-trigger-coverage

## 1. Intent & Context
- **Issue / Ticket:** AH-15
- **Module:** ci
- **Summary:** Both workflows filter `pull_request` to `branches: [main]`, so a pull request targeting anything else runs no job at all. A stacked pull request and a pull request against a `release/*` branch — which `docs` and the project's own branch conventions treat as a legitimate target — arrive with zero checks, and GitHub renders zero checks as an absence rather than as a failure. `gh pr checks` exits `0` on such a pull request with "no checks reported", so the absence reads as a pass to tooling as well as to a reviewer skimming the page. That is the fail-open shape this project exists to remove, sitting in the gate that guards every other gate.
- **Target Module / Layer:** `.github/workflows/ci.yml`, `.github/workflows/compatibility.yml`, `test/test_cli.sh`, `README.md`.

## 2. Requirements & Domain Floor Invariants
- [x] Requirement 1: `pull_request` carries no base-branch filter in either workflow, so every pull request is verified whatever it targets.
- [x] Requirement 2: `push` keeps its `branches: [main]` filter. Pull requests are what needs universal coverage; running the full matrix on every push to every branch would duplicate the same work for no additional evidence.
- [x] Requirement 3: A test asserts both of the above, so a filter cannot be reintroduced without a failing gate saying so.
- [x] Invariant: Must not violate `rules/floor.md`. A pull request that ran no check must not be indistinguishable from one that passed every check.

## 3. Implementation Plan
1. [x] Add a failing assertion to `test/test_cli.sh` covering the `pull_request` and `push` triggers of both workflows.
2. [x] Remove the `branches` filter from the `pull_request` trigger in `.github/workflows/ci.yml` and `.github/workflows/compatibility.yml`.
3. [x] Record the guarantee in `README.md` alongside the contributing commands.
4. [x] Run `harness qa all` and the full suite.

## 4. Verification & QA
- **Automated Test Command:** `env -u STACK_PROFILE npm test`
- **Expected Outcome:** Green suite with zero regressions, including the new assertions in group 36, and a pull request opened against a non-trunk base that reports real checks rather than none.
