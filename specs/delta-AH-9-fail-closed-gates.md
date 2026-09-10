# Delta Spec: AH-9 — fail-closed-gates

## 1. Intent & Context
- **Issue / Ticket:** AH-9
- **Summary:** `rules/floor.md` invariant 1 says a command must never print success after suppressing a required failure. Four of this repository's own gates violate it today, and all four fail the same way: the check runs, the failure is produced, and the exit status discards it. `./setup --verify` prints a `bash -n` syntax error and a missing-frontmatter error and still exits `0`. `harness scan --staged` resolves staged *paths* from the index but greps the *working tree*, so a violation that is staged and then reverted on disk commits clean. `harness scan --install-hook` overwrites a pre-existing `pre-commit` hook with no backup and reports success. A scanner rule whose pattern `grep -E` cannot compile exits `2` into a suppressed stderr and is read as "no match", which is why the shipped `PERF-001` rule has never fired. This delta makes each of those four gates fail closed and adds the test coverage that would have caught them.
- **Target Module / Layer:** `install.sh`, `core/scripts/stack-scan.sh`, `rules/landmines.json`, `core/templates/landmines-template.json`, `test/test_cli.sh`, `README.md`, `CHANGELOG.md`, `package.json`.

## 2. Requirements & Domain Floor Invariants

### Verification exits on failure
- [x] `./setup --verify` exits non-zero when any inspected shell script fails `bash -n`, and names each failing script on stderr. Today `find -exec bash -n {} \;` discards every status, so `find`'s own success is reported as the syntax result.
- [x] `./setup --verify` exits non-zero when any `core/skills/*/SKILL.md` lacks YAML frontmatter or a `name:` field. Today that check runs inside a `find | while` pipeline subshell, so its `log_error` cannot reach the caller's exit status even if one were computed.
- [x] The final success line is printed only when both checks found zero problems. On failure the command prints a count and exits `1`.
- [x] Both checks run to completion before exiting, so one invocation reports every problem rather than only the first.

### The scanner reads what will be committed
- [x] In `--staged` mode the scanner matches against the staged blob content obtained from the index, not against the file on disk. A violation that is `git add`ed and then reverted in the working tree must fail the scan, and a violation present only in the working tree must not.
- [x] Staged content is materialized once per file, before the rule loop, and reused by every rule. Materializing per rule would multiply `git show` invocations by the rule count for no benefit.
- [x] Findings continue to report the repository-relative path and the line number within the scanned content. Because the index blob and the reported path describe the same bytes, the reported line numbers are the line numbers of the commit.
- [x] `--staged` no longer skips a staged path that is absent from the working tree. A file staged as an addition and then deleted on disk is still part of the next commit and must still be scanned.
- [x] `--diff` and `--all` continue to read the working tree. They describe uncommitted work and tracked files respectively, and neither is a statement about the index.
- [x] Materialized content is removed when the scanner exits, on success, failure, or interrupt.

### The pre-commit hook is never destroyed
- [x] `--install-hook` refuses to overwrite an existing `pre-commit` hook that agent-harness did not write. It exits non-zero, prints the hook's path, and prints the one line a user can add to their own hook instead.
- [x] The generated hook carries an identifying marker line. A hook that carries it is agent-harness's own and is rewritten in place, so re-running `--install-hook` is idempotent rather than an error.
- [x] `--install-hook --force` overwrites a foreign hook only after copying it to `pre-commit.harness-backup`, preserving its mode. An existing backup is not overwritten; the command fails instead of destroying two hooks.
- [x] Installation writes through a temporary file in the hooks directory and renames it into place, so an interrupted install cannot leave a truncated hook. **Amended during implementation.** "The hooks directory" was previously hard-coded as `${REPO_DIR}/.git/hooks`, which is wrong in a linked worktree, where `.git` is a file and that path is a directory git never reads. It is now resolved with `git rev-parse --git-path hooks`, matching the `--git-common-dir` idiom AH-3 and AH-4 already use for receipts and ledgers. Installing a hook from a worktree previously created a directory with no effect; it now installs the hook git will actually run.

### An unusable rule is an error, not a silent pass
- [x] Before scanning, every rule pattern is compiled once against empty input. A pattern that `grep -E` rejects (status `2` or higher) aborts the scan with a non-zero exit that names the rule ID and the rules file. A pattern that merely fails to match (status `1`) is valid. **Amended after CI.** The compile check alone is platform-dependent and this requirement was wrong to rely on it. BSD `grep` rejects a `(?!…)` lookahead, but GNU `grep` compiles it, reading the `?` as a literal inside an ordinary group, so the first implementation caught the shipped `PERF-001` on the macOS runner and passed it on the Ubuntu one — the platform most installations run on. A grep-independent check now rejects any pattern containing `(?`, which opens a PCRE group construct that ERE does not define, and the compile check remains for malformed patterns every `grep` rejects. The test asserts the *reason* reported for the lookahead, not merely its rule ID, so the guard cannot quietly narrow back to one platform.
- [x] Validation covers every rule in the file, so one invocation reports every unusable rule rather than only the first.
- [x] `PERF-001` is rewritten as an ERE. Its current `(?!\.iterator|\.values|\[)` is a PCRE negative lookahead that `grep -E` cannot compile, which is why the rule has never produced a finding in this repository or in any project initialized from the template. The replacement matches `.objects.all()` only when the call ends the expression, which is the bounded-query concern the rule documents.
- [x] The identical `PERF-001` in `core/templates/landmines-template.json` is corrected in the same change. Leaving it would make every newly initialized project fail its first scan under the new validation.
- [x] Rules are validated before any file is read, so a malformed ruleset fails immediately rather than after scanning a large tree.

### Invariants
- [x] Invariant: the change must not violate `rules/floor.md`.
- [x] Invariant: the scanner's exit contract is unchanged for callers. `0` means no error-level findings, `1` means findings or an unusable ruleset. No new status is introduced, so the installed pre-commit hook needs no migration.
- [x] Invariant: no new runtime dependency. Bash, Git, `grep`, and the already-required `jq` only.
- [x] Invariant: shell stays portable across the macOS and Ubuntu CI runners. No GNU-only `grep`, `sed`, or `mktemp` flags, and no `\d`, `\b`, or `\+` in the shipped rule patterns.
- [x] Invariant: `install.sh` and `core/scripts/stack-scan.sh` pass `shellcheck -S warning` through `npm run lint`.
- [x] Invariant: `\s` in the shipped `SEC-001` and `SEC-002` patterns is left alone. It is a GNU extension that both CI runners' `grep` accept, it was verified to match on BSD `grep -E`, and rewriting it would be an unrequested change to rules this delta is not fixing.

## 3. Implementation Plan
1. [x] RED — extend `test/test_cli.sh` with a `setup --verify` group asserting non-zero exit and a named script for an injected `bash -n` error, non-zero exit for a frontmatter-less `SKILL.md`, both problems reported in one run, and exit `0` plus the success line on a clean tree.
2. [x] RED — extend `test/test_cli.sh` with a scanner group asserting: a staged violation reverted in the working tree fails `--staged`; a working-tree-only violation passes `--staged` and fails `--diff`; a staged addition deleted from disk is still scanned; reported paths and line numbers refer to staged content; and no temporary artifact survives the run.
3. [x] RED — extend `test/test_cli.sh` with a hook group asserting: a foreign hook is preserved and the command exits non-zero; re-running against agent-harness's own hook succeeds and is idempotent; `--force` backs the foreign hook up with its mode intact; and `--force` refuses when a backup already exists.
4. [x] RED — extend `test/test_cli.sh` with a ruleset group asserting: a lookahead pattern aborts the scan non-zero naming its rule ID; every unusable rule is named in one run; a valid pattern that matches nothing still exits `0`; and the shipped `PERF-001` matches an unbounded `.objects.all()` while not matching `.iterator()`, `.values()`, or a slice.
5. [x] GREEN — add an error counter and a non-subshell frontmatter loop to the `--verify` block in `install.sh`.
6. [x] GREEN — in `core/scripts/stack-scan.sh`, build a parallel array of scan sources before the rule loop, materializing index blobs under one `mktemp -d` with an `EXIT` trap in `--staged` mode; add rule-pattern preflight validation; rewrite the hook installer with a marker, a foreign-hook refusal, and `--force` with a backup.
7. [x] GREEN — correct `PERF-001` in `rules/landmines.json` and `core/templates/landmines-template.json`.
8. [x] Update `README.md` for the hook's new refusal and `--force`, add the `CHANGELOG.md` entry, bump `package.json` to the next unreleased minor, and correct the stale README version badge that the bump exposes.
9. [x] Run `npm run lint`, `./setup --verify`, `harness scan --diff`, `harness spec verify`, the full suite, and the two-axis review.

## 4. Verification & QA
- **Automated Test Command:** `env -u STACK_PROFILE npm test && npm run lint && ./setup --verify`
- **Pre-flight Command:** `./bin/harness qa all`
- **Spec Verification:** `./bin/harness spec verify specs/delta-AH-9-fail-closed-gates.md`
- **Expected Outcome:** The new `test/test_cli.sh` groups pass, its existing fifteen groups stay green, the transaction suites stay green, `shellcheck -S warning` is clean, `./setup --verify` succeeds on a clean tree and fails on a dirtied one, and CI passes on both runners.

## 5. Non-Goals
- The other defects found in the same investigation: `--base <branch>` documented but parsed positionally in `harness branch create` and `harness worktree create`; the unanchored issue-key regex in `harness commit build` that turns `feat/add-2fa-support` into `feat(add-2)`; `config.example.json` acting as a live configuration fallback for repositories that have none; `eval` on config-supplied paths in `lib/config.sh` and `stack-scan.sh`; `harness debt --all` advertised and unimplemented; bash completion advertised while only zsh exists; a failed `git push` in `harness ship` degrading to a warning before the PR is opened; and `harness context` counting archived specs as active. Each is real and each is a different seam. Bundling them would make this diff unreviewable, which is the failure mode `rules/floor.md` invariant 6 exists to prevent.
- Skill-bundle drift detection and a repository-scoped `harness sync`. Installed bundles are copies with no version stamp, and `harness sync` only reaches the global surface, so an initialized repository silently keeps the skills it was installed with. That is the largest gap the investigation found, but it is a new capability rather than a gate that fails open, and it needs its own spec.
- A read path for receipts and ledgers (`list`, `stats`, `prune`). Also a new capability, and the natural companion to the drift work rather than to this one.
- Widening `harness doctor` to validate configuration against `schema.json`, check the pre-commit hook, or detect drift. Doctor's thinness is a gap, not a false success.
- Any change to the scanner's rule schema, severity model, or output format. This delta changes when the scanner refuses to run and which bytes it reads, not what a rule can express.
- Path exclusions and inline suppression for the scanner. Making false positives survivable is worth doing and is unrelated to making true positives detectable.
- Rewriting `\s` to `[[:space:]]` in the shipped patterns. Verified to work on both runners' `grep`; changing it would be a drive-by.

## 6. Open Questions
- **Release numbering.** AH-8 shipped as `2.2.0`, so this is cut as `2.3.0`. The scanner change alters which inputs a gate rejects, which can turn a green pre-commit hook red on a repository that was relying on the working-tree read. That is a corrected defect rather than a compatibility break, so it stays a minor bump, but the CHANGELOG entry must say plainly that scans may now fail where they previously passed.
- **The scanner still reports success when `jq` is absent — deferred.** Without `jq` the rule loop is skipped entirely and the scan prints "passed with 0 errors". That is the same fail-open shape as the four gates this delta closes, and it was found while implementing rule validation rather than during the investigation that scoped it. `jq` is a documented hard requirement and `harness doctor` already reports it as missing, so the exposure is narrow; adding a fifth requirement mid-implementation would have widened an approved scope. It belongs with the `harness doctor` work already listed as a non-goal.
- **`--force` versus a prompt for the hook.** A prompt cannot be answered when the installer runs from a script or from an agent, so the refusal is the default and `--force` is the explicit override. If foreign hooks turn out to be the common case rather than the exception, the better answer is a chained hook that calls both, which is a larger design than this delta.
