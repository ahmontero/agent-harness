# Delta Spec: AH-47 — ci-scaffolding

## 1. Intent & Context
- **Issue / Ticket:** AH-47
- **Module:** ci
- **Summary:** `harness init` installs surfaces, rules, a configuration and optionally the scanner's hook — and nothing for CI. Every local gate is bypassable with `--no-verify`, so CI is the only place a project's floor is actually enforced; this repository's own CI is what caught three defects in this series. An adopter receives none of it and has to write the pipeline themselves, which means most will not.
- **Target Module / Layer:** `core/templates/ci/` (new), `install.sh`, `core/scripts/lib/git.sh`, `test/test_cli.sh`

## 2. Requirements & Domain Floor Invariants
- [ ] R1: `harness init --with-ci` writes a pipeline for the configured `ci.provider`: `.github/workflows/agent-harness.yml` for github, `.gitlab/agent-harness.yml` for gitlab.
- [ ] R2: Both destinations are **additive**. A GitHub workflow is one file among many by design; for GitLab the file is an `include:` target, never `.gitlab-ci.yml` itself, so an adopter's existing pipeline cannot be touched even with `--force`.
- [ ] R3: A file carrying the marker is ours and is rewritten idempotently. A file without it is refused, and `--force` backs it up before replacing — the same contract `install_managed_hook` has for hooks.
- [ ] R4: `azure` is refused by name, telling the reader what to do instead. Shipping an Azure Pipelines template nobody here can run would be a claim this project cannot execute.
- [ ] R5: The generated pipeline checks out with full history, installs the harness, and runs `harness config validate`, `harness commit check --branch`, and `harness qa all`. Full history because both `--branch` gates resolve a merge base and a depth-1 clone has none — the mistake this repository's own CI carries a comment about.
- [ ] Invariant: Must not violate `rules/floor.md` — 1 (gates fail closed), 3 (claims are executable), 6 (changes stay scoped).

**Non-goals.** `harness init` without `--with-ci` writes no pipeline; changing what a bare `init` does would alter behaviour nobody asked to change. The template does not pin a harness version — an adopter who wants one edits the file they now own. `harness uninstall` does not remove it: a pipeline is a file the repository commits and owns, like `AGENTS.md` and `rules/`, and those are explicitly what uninstall leaves alone.

## 3. Implementation Plan
1. [ ] RED: `init --with-ci` writes the github pipeline; re-running is idempotent; a foreign file is refused and `--force` backs it up; gitlab writes the include target and leaves `.gitlab-ci.yml` untouched; azure refuses.
2. [ ] Add the two templates under `core/templates/ci/`.
3. [ ] Generalize the marker/refuse/backup write into `lib/git.sh` beside `install_managed_hook`, and call it from `install.sh`.
4. [ ] Run `harness scan --branch`, `bash test/test_cli.sh`, ShellCheck and `./setup --verify`.

## 4. Verification & QA
- **Automated Test Command:** `bash test/test_cli.sh --group 58`
- **Expected Outcome:** Green suite with zero regressions; the generated GitHub workflow is valid YAML that runs the three harness gates.
