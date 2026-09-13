# Delta Spec: AH-33 — minor-gaps

## 1. Intent & Context
- **Issue / Ticket:** AH-33
- **Module:** cli
- **Summary:** Three small gaps left by the audit, each independent: the README claims sixteen protocols are bundled inside the workflows and six are bundled nowhere; `harness init` names the gates it left unset without saying what to write; and this repository's own TDD loop is its whole five-minute suite, which the protocol it ships calls "fast feedback mode".
- **Target Module / Layer:** `core/skills/catalog.json`, `README.md`, `install.sh`, `test/test_cli.sh`, `harness.config.json`.

### The README claim, precisely

`README.md` introduces its protocol list with "The protocols below are bundled privately inside those workflows". Six of the sixteen are referenced by no workflow: `commit`, `conflicts`, `debt`, `doctor`, `questionnaire` and `scan`. Four of those six document CLI commands and duplicate `harness --help`; two are capabilities with no CLI behind them and no path to being invoked in the default mode at all. `conflicts` is the one that matters — an agent that hits a merge conflict while integrating has no protocol for it, which happened in this repository's own pull request #24.

### Why the TDD loop is the sharpest of the three

`harness.config.json` sets `qa.tddCommand` to `bash test/test_cli.sh`, which is 48 groups and about five minutes. `core/skills/qa/SKILL.md` describes `harness qa tdd` as "Run single test in fast feedback mode". The RED-GREEN cycle this project exists to enforce is, in this project, a five-minute wait per iteration — so the harness's own discipline is the one its configuration makes most expensive to follow.

## 2. Requirements & Domain Floor Invariants
- [ ] R1: `conflicts` is published into the `implement` and `fix` bundles as `references/conflicts.md`. Those are the workflows that integrate work and can meet a conflict; `questionnaire` stays expert-only, being a discovery tool rather than a delivery step.
- [ ] R2: The README distinguishes the protocols bundled inside the workflows from those available only through `--expert`, so the list stops claiming something untrue of six of its entries.
- [ ] R3: `harness init` prints the exact JSON to paste for each gate it left unset, not only the gate's name. The friction is not knowing a key is missing; it is knowing what to write and where.
- [ ] R4: `test/test_cli.sh` accepts a filter so one group can be run on its own, and refuses a filter that matches no group rather than passing over an empty selection.
- [ ] R5: `qa.tddCommand` in this repository runs a filtered group, so the project's own fast feedback loop is fast.
- [ ] R6: The full suite is unchanged when no filter is given, and every group still runs in CI.
- [ ] R7: This repository's `qa.lintCommand` runs the same ShellCheck its CI runs. Found while implementing R4: the gate was `./setup --verify`, which is `bash -n`, while ShellCheck ran only in the workflow — so `harness qa all` reported a passing lint gate over code CI rejected, and a ShellCheck failure reached a published pull request. A local gate that checks less than the real one is the fail-open shape this project keeps closing, in the project's own configuration.
- [ ] Invariant: Must not violate `rules/floor.md`. Invariant 1 in particular — a filter that matched nothing and exited zero would be a gate that could not run reporting a pass, which is what R4's refusal exists to prevent.

### Non-goals
- `harness config set`. Writing one key is a once-per-project action, and a command for it would add dotted-path parsing, type inference between a boolean `false` and the string `"false"`, atomic writing and its own validation. R3 addresses the real friction without new surface, and leaves the configuration file the single place a project's decisions are recorded.
- Publishing the four CLI-documenting primitives into curated mode. They duplicate `harness --help` in every bundle of every runtime, and the curated surface exists to stay small.
- Parallelising the suite. R5 makes one group cheap to run; making all 48 faster is a different problem with different risks.

## 3. Implementation Plan
1. [ ] RED — assert `conflicts` reaches the two bundles, that the README separates bundled from expert-only, that `init` prints pasteable JSON, and that the suite filter selects one group and refuses a filter matching none.
2. [ ] Add `conflicts` to the `implement` and `fix` reference lists in the catalog.
3. [ ] Correct the README's protocol list introduction and mark the expert-only entries.
4. [ ] Emit a pasteable JSON fragment from `write_detected_config` for the gates left unset.
5. [ ] Add the group filter to `test/test_cli.sh` and point `qa.tddCommand` at it.
6. [ ] Point `qa.lintCommand` at the ShellCheck run CI performs, so the two gates check the same thing.
7. [ ] Run `harness qa all`.

## 4. Verification & QA
- **Automated Test Command:** `bash test/test_cli.sh`
- **Expected Outcome:** The new assertions pass; groups 2b, 20, 36, 37 and 38 stay green, which is what proves the catalog and installer changes are coherent — they already assert the workflow contract, surface manifests, trigger coverage, bundle digests and init's detection output. `harness qa all` exits 0 and the filtered form runs one group in seconds.
