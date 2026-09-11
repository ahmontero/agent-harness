# Delta Spec: AH-18 — ship-guards

## 1. Intent & Context
- **Issue / Ticket:** AH-18
- **Module:** ship
- **Summary:** `harness ship` pushes and opens a pull request with no guard on what it is publishing. Run on the trunk it pushes the trunk and opens a pull request from `main` into `main`. Run with uncommitted work it pushes a branch that is missing it and says nothing. It asks for no confirmation before a push, which the project's own branch conventions forbid an agent from performing unasked. Its first positional argument is taken as the target branch, so `harness ship --force` targets a branch named `--force`. On a detached HEAD it pushes an empty refspec. When `gh` is missing it prints a suggestion and exits `0`, reporting success for a run that opened nothing, and when `gh pr create --fill` fails it retries interactively, which hangs where there is no terminal. The command's own help advertises a "build commit" step it has never performed.
- **Target Module / Layer:** `core/scripts/stack-pr.sh`, `bin/harness`, `core/scripts/stack-completion.sh`, `test/test_cli.sh`, `README.md`, `CHANGELOG.md`, `package.json`.

## 2. Requirements & Domain Floor Invariants
- [x] Requirement 1: Every guard runs before any mutation, and each refusal names what it found and leaves the repository untouched.
- [x] Requirement 2: `ship` refuses to publish the branch it is targeting, refuses a detached HEAD, refuses a branch with no commits ahead of its target, and refuses uncommitted changes to tracked files. Untracked files are reported rather than refused: they are not going to be pushed either way, and blocking on a scratch file would retire the command.
- [x] Requirement 3: `ship` asks before pushing, and refuses when there is no terminal to ask on. `--yes` is how a human confirms in advance. This is the project's own rule for agents, enforced by the command rather than left to the operator.
- [x] Requirement 4: Options are parsed rather than swallowed as a target branch, and an unknown one is refused.
- [x] Requirement 5: A run that pushed but opened no pull request exits non-zero and says exactly which half happened. `gh pr create` is never retried interactively.
- [x] Requirement 6: `--dry-run` reports every decision and mutates nothing, matching the flag `worktree remove` already offers for its destructive path.
- [x] Requirement 7: The help text stops advertising a "build commit" the command does not perform.
- [x] Invariant: Must not violate `rules/floor.md`. Publication is outward-facing and effectively irreversible; the command must not perform it on the strength of a default.

## 3. Implementation Plan
1. [x] Add failing coverage to `test/test_cli.sh` for each refusal, for `--dry-run`, and for the confirmed happy path through a local bare remote and a configured `ci.prCommand`.
2. [x] Parse arguments in `core/scripts/stack-pr.sh` and add the guards ahead of the QA run.
3. [x] Require confirmation before the push, and make a missing or failing pull-request step exit non-zero.
4. [x] Correct the help text in `bin/harness` and the description in `core/scripts/stack-completion.sh`.
5. [x] Run `harness qa all` and the full suite.

## 4. Verification & QA
- **Automated Test Command:** `env -u STACK_PROFILE npm test`
- **Expected Outcome:** Green suite with zero regressions, including the new assertions in group 39, and a `harness ship` on the trunk that refuses instead of publishing it.
