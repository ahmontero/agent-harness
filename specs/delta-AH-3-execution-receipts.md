# Delta Spec: AH-3 — execution-receipts

## 1. Intent & Context
- **Issue / Ticket:** AH-3
- **Summary:** Add a local, privacy-preserving event receipt for composite workflow executions. Receipts create the stable measurement contract needed by future statistics without introducing a workflow runner or remote telemetry.
- **Target Module / Layer:** `core/scripts/stack-receipt.sh`, CLI dispatch/completion, composite workflow contracts, tests, and documentation.

## 2. Requirements & Domain Floor Invariants
- [x] `harness receipt start <implement|fix|investigate> [--issue <token>]` atomically creates a unique JSONL receipt and prints its run ID.
- [x] `harness receipt phase <run_id> <phase_token> <started|passed|failed|blocked|skipped>` appends a schema-valid event.
- [x] `harness receipt finish <run_id> <completed|failed|blocked|cancelled>` appends exactly one terminal event and rejects further events.
- [x] Receipts are stored under Git metadata, never in the working tree, and are shared by worktrees of the same repository.
- [x] The schema contains only allowlisted operational metadata: schema version, run ID, timestamp, workflow, event, phase/status or outcome, issue token, profile, and branch.
- [x] Inputs reject traversal, whitespace, oversized tokens, unsupported workflows/statuses/outcomes, missing runs, and duplicate finish attempts.
- [x] Concurrent starts produce unique run IDs and valid independent receipts.
- [x] Composite workflows instruct agents to emit start, phase, and finish events without weakening engineering gates if receipt recording fails.
- [x] Invariant: no prompt, arbitrary evidence text, source code, secret, or remote telemetry is recorded.

## 3. Implementation Plan
1. [x] Add CLI tests for lifecycle, schema, storage location, validation, terminal immutability, and concurrent uniqueness.
2. [x] Implement a small receipt command using Bash, Git, and `jq` only.
3. [x] Add dispatcher/help/completion integration.
4. [x] Add receipt instructions to the three composite workflows and public documentation.
5. [x] Run static scan, all delta-spec verifications, and the complete test suite.

## 4. Verification & QA
- **Automated Test Command:** `bash test/test_cli.sh`
- **Expected Outcome:** Valid lifecycle events form parseable JSONL; invalid and post-terminal writes fail; concurrent runs remain unique; all existing tests stay green.

## 5. Non-Goals
- Aggregate metrics or implement `harness stats`.
- Execute workflows, activate agents, resume runs, or enforce phase ordering beyond terminal immutability.
- Capture durations supplied by agents, token/cost data, free-form evidence, prompts, diffs, or file paths.
- Send telemetry outside the local Git repository.
