# Delta Spec: AH-5 — installer-transactions

## 1. Intent & Context
- **Issue / Ticket:** AH-5
- **Summary:** `install.sh` mutates the user's home directory (`~/.claude`, `~/.gemini`, `~/.codex`, `~/.agents`, `~/.local/bin`) and an arbitrary target repository with unguarded `mkdir -p`, `cp`, `ln -sf`, and `rm -rf`. It runs under `set -eo pipefail`, so a failure part-way through leaves a half-installed skill surface with no record of what changed and no way back. This delta adapts the reversible-transaction mechanism from the author's `easys-stack` toolkit: every installer mutation is journaled before it happens, an `ERR` trap restores the previous filesystem state automatically, and a committed installation can be undone explicitly with `install.sh --rollback`.
- **Target Module / Layer:** `core/scripts/lib/transaction.sh` (new), `install.sh`, `test/test_transaction_lib.sh` (new), `test/test_install_transaction.sh` (new), `.github/workflows/ci.yml`, `package.json`, `README.md`, `CHANGELOG.md`, `docs/PROVENANCE.md`.

## 2. Requirements & Domain Floor Invariants

### Transaction library
- [x] `core/scripts/lib/transaction.sh` provides a journaled mutation API: `transaction_begin`, `transaction_commit`, `transaction_ensure_directory`, `transaction_symlink`, `transaction_unlink`, `transaction_copy`, `transaction_write_command`, `transaction_remove_tree`, `transaction_rollback_dir`, and `transaction_rollback_last`.
- [x] `transaction_record` refuses any mutation attempted outside an active transaction, and rejects empty or newline-bearing paths.
- [x] Journals live under `${HARNESS_STATE_DIR}`, else `${XDG_STATE_HOME}/agent-harness`, else `${HOME}/.local/state/agent-harness`, created with `umask 077`.
- [x] `transaction_record` classifies a pre-existing path as `symlink`, `file`, `directory`, or `absent`, backs up file content and link targets, and fails closed on any other object kind.
- [x] `transaction_remove_tree` removes a managed directory bottom-up, journaling every contained file, symlink, and directory so the whole tree is restorable. This primitive does not exist upstream and is required because `install.sh` deletes managed skill directories.
- [x] A mutation or restore whose target cannot be removed aborts and reports, rather than writing *through* whatever now occupies that path. Writing through a stale symlink-to-directory would deposit files outside the journaled location.
- [x] Rollback replays journal entries in reverse order. An entry it cannot restore marks the journal `rollback-failed`, preserves the journal, and exits non-zero.
- [x] `transaction_begin` refuses to nest, and `transaction_commit` restores the caller's previous `ERR` trap. A transaction with zero operations commits as `no-op` and publishes no rollback pointer.
- [x] Failure injection is opt-in through `HARNESS_ENABLE_FAILURE_INJECTION=true` plus `HARNESS_TEST_FAIL_AFTER=<n>`, and returns status 97. It is inert unless both are set.

### Installer wiring
- [x] `install.sh` runs under `set -Eeo pipefail` so the `ERR` trap propagates into installer functions.
- [x] Every filesystem mutation in `install_cli`, `install_target_repo`, `install_global`, `install_skill_surface`, `install_workflow_bundle`, and `remove_managed_skill` is performed through a `transaction_*` primitive.
- [x] `--target`, `--global`, `--sync-only`, `--cli-only`, and `--guided` runs are wrapped in a single transaction that commits only after the whole install succeeds.
- [x] A failure part-way through an install restores the target and home trees to their exact prior state and marks the journal `rolled-back`.
- [x] `install.sh --rollback` undoes the last committed transaction exactly once; a second attempt exits non-zero. It refuses a journal pointer outside its own state root.
- [x] `--rollback` cannot be combined with any installation option.
- [x] Read-only `--verify` performs no mutation and therefore opens no transaction.

### Continuous integration
- [x] `ci.yml` runs `shellcheck -S warning` over `bin`, `core/scripts`, `install.sh`, and `setup` on both runners, and the lint step fails the build.
- [x] `ci.yml` runs `test/test_transaction_lib.sh` and `test/test_install_transaction.sh`, and sets `fail-fast: false` so a macOS-only regression is not masked by a Linux failure.

### Invariants
- [x] Invariant: the change must not violate `rules/floor.md`.
- [x] Invariant: portable across the Bash versions on `ubuntu-latest` and `macos-latest`, including Bash 3.2. No GNU-only flags.
- [x] Invariant: pre-existing unmanaged paths keep their current treatment. `install.sh` preserves and warns; it must not start deleting or failing closed on foreign files.
- [x] Invariant: journals stay local, contain no credentials, and are never written into the working tree.

## 3. Implementation Plan
1. [x] RED — `test/test_transaction_lib.sh` exercising the library API directly: state-root precedence, path validation, untracked-mutation refusal, object classification, tree removal and restore, reverse-order rollback, `rollback-failed` preservation, `ERR` trap save/restore, and nesting refusal.
2. [x] GREEN — port `transaction.sh` into `core/scripts/lib/` with the `HARNESS_*` prefix and add `transaction_remove_tree`.
3. [x] RED — `test/test_install_transaction.sh` covering injected mid-install failure, explicit rollback of a successful `--target` install, double rollback, rollback with no prior transaction, an unsafe journal pointer, and a corrupted journal entry.
4. [x] GREEN — route every `install.sh` mutation through the library, add `--rollback`, and switch to `set -Eeo pipefail`.
5. [x] Add the ShellCheck and new suite steps to `ci.yml`, wire both suites into `package.json`, then run `harness scan --diff`, `harness spec verify specs/delta-AH-5-installer-transactions.md`, and the full suite.

## 4. Verification & QA
- **Automated Test Command:** `bash test/test_transaction_lib.sh && bash test/test_install_transaction.sh && bash test/test_cli.sh && ./setup --verify`
- **Expected Outcome:** Both new suites pass, the existing `test_cli.sh` groups stay green, `./setup --verify` succeeds, and `shellcheck -S warning` is clean over `bin`, `core/scripts`, `install.sh`, and `setup`.

## 5. Non-Goals
- The `kcov` coverage job. Coverage measurement is a separate proposal.
- Migrating `core/skills/catalog.json` to the upstream `schemaVersion 2` asset manifest, or making rule, context-alias, CLI, and completion destinations manifest-driven.
- `--plan` / `--check` read-only drift modes, collision fail-closed semantics, and completion-block installation, all of which exist upstream but describe a different installer contract.
- Making `core/scripts/stack-completion.sh` transactional. It is invoked by the user, not by `install.sh`.
- Adding `set -u` to `install.sh`.
- Porting `.claude-plugin/plugin.json`, the ADR template, or `sync --check`.
