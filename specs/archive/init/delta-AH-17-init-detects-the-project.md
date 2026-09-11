# Delta Spec: AH-17 — init-detects-the-project

## 1. Intent & Context
- **Issue / Ticket:** AH-17
- **Module:** init
- **Summary:** `harness init` copies a fixed template that declares every repository a Python "backend" running `pytest`, with a GitHub issue prefix of `PROJ` and a trunk branch of `main`. In a Node, Go, or Rust project the first command a new user runs — `harness qa all` — therefore invokes `pytest`, fails, and reports the lint and type gates as unrunnable. The README already promises that `harness init` detects the language and test runner, so the claim exists and the code does not honour it, which is the AH-11 shape: an advertised claim that is not executable. The fix is to write commands the target actually evidences and to leave unevidenced ones unset, saying so, rather than to assert a stack nobody verified. Writing `false` — the documented way to record that a project genuinely has no such gate, and the right answer for a Go or Rust type checker — is currently rejected by `schema.json`, so `harness config validate` fails a configuration `harness qa` handles correctly.
- **Target Module / Layer:** `install.sh`, `schema.json`, `core/templates/stack-config-template.json`, `test/test_cli.sh`, `README.md`, `CHANGELOG.md`, `package.json`.

## 2. Requirements & Domain Floor Invariants
- [x] Requirement 1: `harness init` writes one profile per ecosystem it finds evidence of — Python, Node, Go, Rust — each carrying its own `detect` block, so a polyglot repository resolves the right profile per directory through the mechanism the configuration format already provides.
- [x] Requirement 2: Every command written is evidenced by a file in the target. A `test` script in `package.json`, `[tool.ruff]` in `pyproject.toml`, `manage.py` for Django, `.golangci.yml` for golangci-lint. What is not evidenced is left unset, and `init` names it so the user knows what to fill in.
- [x] Requirement 3: `init` asserts nothing it cannot verify. No `PROJ` issue prefix, and no `git.trunkBranch`: trunk detection at runtime already reads the repository, and a hardcoded `main` is wrong in any repository whose trunk is `master`.
- [x] Requirement 4: A target with no recognizable ecosystem gets a profile with no commands and a message saying which keys to set. An unconfigured gate that reports it could not run is correct; a configured gate that runs the wrong tool is not.
- [x] Requirement 5: `schema.json` accepts `false` as well as a string for `qa.testCommand`, `qa.tddCommand`, `qa.lintCommand`, `qa.typeCheckCommand`, and `qa.testRunner`, so the value `stack-qa.sh` documents validates.
- [x] Invariant: Must not violate `rules/floor.md`. Everything `init` writes must be either read from the target or absent.

## 3. Implementation Plan
1. [x] Add failing coverage to `test/test_cli.sh`: a Node, a Go, a Django and an unrecognizable repository each get the right profile, `harness config validate` passes on every generated configuration, and `false` validates.
2. [x] Widen the `qa` command types in `schema.json`.
3. [x] Replace the template copy in `install_target_repo` with evidence-based detection, written through the installation transaction.
4. [x] Remove `core/templates/stack-config-template.json`, which nothing reads once detection replaces it.
5. [x] Run `harness qa all` and the full suite.

## 4. Verification & QA
- **Automated Test Command:** `env -u STACK_PROFILE npm test`
- **Expected Outcome:** Green suite with zero regressions, including the new assertions in group 38, and a freshly initialized Node repository whose `harness qa all` runs that project's own commands rather than `pytest`.
