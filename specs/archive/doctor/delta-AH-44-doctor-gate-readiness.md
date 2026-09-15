# Delta Spec: AH-44 — doctor-gate-readiness

## 1. Intent & Context
- **Issue / Ticket:** AH-44
- **Module:** doctor
- **Summary:** `harness doctor` reports a healthy environment for a repository whose lint, type and test gates cannot run, because it never asks whether they are configured. A freshly initialized project answers `0 errors` to `doctor` and then fails `qa all` and refuses `ship` — so the command whose job is to say what is wrong is silent about the one thing that will stop the next command. `init` warns about it once, at install time, and nothing reports it afterwards.
- **Target Module / Layer:** `core/scripts/lib/qa.sh` (new), `core/scripts/stack-qa.sh`, `core/scripts/stack-doctor.sh`, `test/test_cli.sh`

The load-bearing constraint is that doctor must not answer this question separately from `harness qa all`. Gate resolution lives inside `stack-qa.sh` today; a second copy in doctor would drift, which is the failure `lib/specs.sh` and `lib/surface.sh` were each extracted to prevent. Resolution moves to a shared library and both commands read it.

## 2. Requirements & Domain Floor Invariants
- [ ] R1: `harness doctor` reports the state of the test, lint and type gates: configured, declared absent, or unable to run.
- [ ] R2: A gate that cannot run is an **error**, and doctor exits non-zero. It is the same verdict `qa all` reaches, and `rules/floor.md` invariant 1 is that a gate which could not run is not a gate that passed.
- [ ] R3: A gate the configuration declares absent with `false` is reported and is **not** a problem: it leaves the exit status alone. The refusal has to stay satisfiable, which is why `false` exists.
- [ ] R4: Every gate appears in `doctor --json` under section `qa` carrying its state, including the ones that are fine.
- [ ] R5: Doctor and `qa all` resolve every gate through one implementation, so they cannot disagree about what a gate resolves to or whether it can run.
- [ ] Invariant: Must not violate `rules/floor.md` — in particular 1 (gates fail closed), 3 (claims are executable) and 6 (changes stay scoped).

**Non-goals.** Doctor does not execute the gates; it reports whether they could run. `qa.scanMode` is already enum-validated by `schema.json` and reported by section 7, so it is not repeated here. Repairing an unconfigured gate under `--fix` is out of scope: the correct command is a project decision, and guessing it is what `init`'s detection already refuses to do.

## 3. Implementation Plan
1. [ ] RED: a fixture whose three gates are unconfigured asserts `doctor` exits non-zero and names each gate; a fixture declaring them `false` asserts it does not.
2. [ ] Extract gate resolution and classification into `core/scripts/lib/qa.sh`, consumed by `stack-qa.sh`.
3. [ ] Add doctor's QA gate section, reading that library.
4. [ ] Assert R5 directly: for one fixture, doctor's per-gate state matches `qa all --json`'s per-gate status.
5. [ ] Run `harness scan --branch`, `bash test/test_cli.sh`, ShellCheck and `./setup --verify`.

## 4. Verification & QA
- **Automated Test Command:** `bash test/test_cli.sh --group 56`
- **Expected Outcome:** Green suite with zero regressions, and `harness doctor` exiting non-zero on the unconfigured fixture while leaving the declared-absent fixture at zero.
