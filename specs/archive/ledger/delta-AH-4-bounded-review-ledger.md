# Delta Spec: AH-4 — bounded-review-ledger

## 1. Intent & Context
- **Issue / Ticket:** AH-4
- **Summary:** `/harness-implement` runs seven phases inside a single agent context with no durable record of what completed and no bounded exit from its review gate. A workflow whose review keeps finding issues either loops indefinitely or the agent silently drops findings, and a compacted context can re-run phases that already passed. This delta adapts the two runtime-agnostic mechanisms of `superpowers:subagent-driven-development` — a durable progress ledger and a bounded fix loop with mandatory adjudication — while deliberately excluding its subagent dispatch, which depends on Claude Code primitives and would break the five-runtime compatibility contract.
- **Target Module / Layer:** `core/scripts/stack-ledger.sh` (new), `bin/harness`, `core/scripts/stack-completion.sh`, `core/skills/implement/SKILL.md`, `core/skills/review/SKILL.md`, `test/test_cli.sh`, `docs/PROVENANCE.md`, `README.md`, `CHANGELOG.md`.

## 2. Requirements & Domain Floor Invariants

### Progress ledger
- [x] `harness ledger start <run_id>` creates `<git-common-dir>/agent-harness/ledgers/<run_id>.md` whose first line is `# Harness ledger — run: <run_id>`, and is idempotent for an existing ledger of the same run.
- [x] `harness ledger append <run_id> <phase|ruling|deferred|parked|complete> <text>` appends exactly one UTC-timestamped line and rejects any other kind.
- [x] `harness ledger show <run_id>` prints the whole ledger; `harness ledger rulings <run_id>` prints only `ruling` and `parked` lines, in the order they were recorded.
- [x] The ledger `run_id` is the identifier returned by `harness receipt start`, so the machine-readable receipt and the human-readable ledger join on one key.
- [x] Ledgers are stored under the Git common directory with `umask 077`, are shared by every worktree of the same repository, and are never written into the working tree.
- [x] Input validation rejects run IDs failing `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`, path traversal, and text longer than 512 bytes; operating on a missing ledger exits non-zero with a diagnostic.
- [x] Free-form narrative text is permitted in a ledger line. This is the property that separates the ledger from an AH-3 receipt, and it is the reason the ledger is a separate artifact rather than a receipt event.

### Bounded fix loop and adjudication
- [x] Phase 7 of `/harness-implement` gains an explicit fix loop with a hard cap of three rounds. One round is one fix plus one re-verification scoped to the amended code.
- [x] Every round appends `round <R>/3 (<X> addressed, <Y> open)` plus the open findings as one-liners to the ledger before the next round begins.
- [x] Minor findings never enter the loop; they are appended as `deferred` and reported in the final response.
- [x] When round three still leaves findings open, the agent stops fixing and adjudicates every open finding as either `parked` with a recorded ruling, or load-bearing.
- [x] Discarding a finding without a ledger line is forbidden; adjudicating before the cap is reached is forbidden.
- [x] A load-bearing finding at the cap terminates the workflow as `blocked` via `harness receipt finish <run_id> blocked`, and the workflow never reports `[IMPLEMENT: COMPLETE]`.
- [x] The final agent response reproduces every `ruling` and `parked` line from the ledger, exhaustively and in recorded order.

### Invariants
- [x] Invariant: the change must not violate `rules/floor.md`.
- [x] Invariant: no requirement depends on subagent dispatch, per-role model selection, subagent resumption, or any other Claude Code exclusive primitive; the workflow behaves identically under Antigravity, Claude Code, Codex, Cursor, and `.agents`.
- [x] Invariant: the AH-3 receipt schema is unchanged, and no free-form evidence, prompt, diff, or source text is ever added to a receipt.
- [x] Invariant: no ledger content leaves the local repository.
- [x] Invariant: `core/scripts/stack-ledger.sh` passes `shellcheck -S warning`, which AH-5 turned into a blocking CI gate through `npm run lint`. The `lint` and `typeCheckCommand` globs already cover `core/scripts`, so the new script is linted without any wiring change.
- [x] Invariant: the ledger's storage root deliberately differs from the AH-5 transaction journal root. Journals are machine-scoped because `install.sh` mutates `$HOME`, so they live under `HARNESS_STATE_DIR` or the XDG state directory. Ledgers are repository-scoped and join an AH-3 receipt by `run_id`, so they live beside receipts under the Git common directory. Neither location is a precedent for the other.

## 3. Implementation Plan
1. [x] RED — add `test/test_cli.sh` cases covering ledger lifecycle, storage under the Git common directory, worktree sharing, kind validation, run-ID and traversal rejection, oversized text rejection, missing-ledger failure, and the `rulings` filter.
2. [x] GREEN — implement `core/scripts/stack-ledger.sh` using Bash and Git only. The ledger is Markdown, so `jq` is not a dependency.
3. [x] Wire `ledger` into `bin/harness` dispatch and help text, and into `core/scripts/stack-completion.sh`.
4. [x] Amend `core/skills/implement/SKILL.md` with the ledger contract, the three-round loop, the adjudication gate, new anti-rationalization rows, and an updated state anchor; amend `core/skills/review/SKILL.md` so review findings are classified as Critical, Important, or Minor for the loop.
5. [x] Update `docs/PROVENANCE.md` so the `obra/superpowers` row records this adapted method and cites `subagent-driven-development` at `b36e082`, then run `npm run lint`, `harness scan --diff`, `harness spec verify specs/delta-AH-4-bounded-review-ledger.md`, and the full suite.

## 4. Verification & QA
- **Automated Test Command:** `env -u STACK_PROFILE npm test && npm run lint && ./setup --verify`
- **Expected Outcome:** New ledger cases pass inside `test/test_cli.sh`; its thirteen existing groups stay green; `test/test_transaction_lib.sh` and `test/test_install_transaction.sh` stay green; `shellcheck -S warning` is clean; and `./setup --verify` succeeds. CI already runs `test/test_cli.sh` directly, so the new cases need no workflow change.

## 5. Non-Goals
- Dispatch implementer or reviewer subagents, select models per role, or run work in parallel. That surface belongs to a separate `harness-orchestrate` proposal gated as Claude Code only.
- Copy the `superpowers` prompt templates or its `sdd-workspace`, `task-brief`, and `review-package` scripts. Only the method is adapted, so no third-party notice obligation is created.
- Extend the ledger or the bounded loop to `/harness-fix` or `/harness-investigate`.
- Change the AH-3 receipt schema, add durations, or record token and cost data.
- Version ledgers in Git, publish them, or transmit them anywhere.
- Route ledger writes through the AH-5 transaction library, or make them reversible. A ledger is an append-only record of what happened, so rolling one back would destroy the evidence it exists to preserve.
