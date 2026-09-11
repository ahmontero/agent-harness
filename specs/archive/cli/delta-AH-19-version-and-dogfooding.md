# Delta Spec: AH-19 — version-and-dogfooding

## 1. Intent & Context
- **Issue / Ticket:** AH-19
- **Module:** cli
- **Summary:** The whole drift model turns on which version of agent-harness is installed — every surface manifest records one, and `harness sync` compares against it — yet there is no way to ask. Upgrading is equally undiscoverable: it is `cd` to a checkout nobody's notes name, `git pull`, then `./setup --sync-only`. Two smaller claims are also unbacked: `completion` is dispatched and documented in the README but absent from `harness --help`, and `forge` is accepted by the dispatcher and offered by the shell completion while no such binary exists. Finally, the repository does not run its own scanner or its own configuration validator in CI, so the two commands it asks every user to trust are the two it never exercises on itself.
- **Target Module / Layer:** `bin/harness`, `core/scripts/stack-version.sh` (new), `core/scripts/stack-upgrade.sh` (new), `core/scripts/stack-completion.sh`, `.github/workflows/ci.yml`, `specs/delta-AH-11-truthful-core-hardening.md`, `test/test_cli.sh`, `README.md`, `CHANGELOG.md`, `package.json`.

## 2. Requirements & Domain Floor Invariants
- [x] Requirement 1: `harness version` reports the installed version, the checkout it is running from, and that checkout's revision, so the number a manifest records can be checked against the code actually running.
- [x] Requirement 2: `harness upgrade` updates the checkout and re-synchronizes every managed surface. It refuses a checkout that is not a Git clone or has uncommitted changes, and `--check` reports what an upgrade would do while mutating nothing.
- [x] Requirement 3: The upgrade script is parsed in full before it executes, because `git pull` rewrites the file bash is reading.
- [x] Requirement 4: Every command the dispatcher routes appears in `harness --help`, asserted structurally so the two cannot drift apart again.
- [x] Requirement 5: `forge` stops being offered. The dispatcher and the shell completion advertised a binary that has never existed.
- [x] Requirement 6: CI runs `harness scan --all` and `harness config validate` against this repository. The two commands it asks every user to trust were the two it never exercised on itself.
- [x] Requirement 7: `specs/delta-AH-11-truthful-core-hardening.md` is archived. It was delivered in `7ea3705`, and an active spec for shipped work makes `harness context` overstate what is in flight.
- [x] Invariant: Must not violate `rules/floor.md`. `upgrade` mutates a checkout, so it refuses rather than guesses, and reports what it changed.

## 3. Implementation Plan
1. [x] Add failing coverage to `test/test_cli.sh` for `version`, for the `upgrade` refusals and `--check`, for the help/dispatcher correspondence, for the absence of `forge`, and for the CI dogfooding steps.
2. [x] Add `core/scripts/stack-version.sh` and `core/scripts/stack-upgrade.sh`, and route both from `bin/harness`.
3. [x] List `completion`, `version` and `upgrade` in `harness --help`, and remove `forge` from the dispatcher and the completion.
4. [x] Add the scanner and configuration-validator steps to `.github/workflows/ci.yml`.
5. [x] Archive the delivered AH-11 spec, and run `harness qa all` and the full suite.

## 4. Verification & QA
- **Automated Test Command:** `env -u STACK_PROFILE npm test`
- **Expected Outcome:** Green suite with zero regressions, including the new assertions in group 40, and a `harness --help` that names every command the dispatcher will accept.
