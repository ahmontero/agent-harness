# Delta Spec: AH-7 — orchestrate-dispatch

## 1. Intent & Context
- **Issue / Ticket:** AH-7
- **Summary:** AH-4 adapted the two runtime-agnostic halves of `superpowers:subagent-driven-development` — a durable progress ledger and a bounded fix loop with mandatory adjudication — and deliberately excluded the other half, because subagent dispatch and per-role model selection depend on Claude Code primitives that the five-runtime compatibility contract does not admit. This delta delivers that excluded half as `/harness-orchestrate`, a fourth public workflow installed only into Claude Code, and turns the compatibility contract from "the same surface in every runtime" into "a declared surface per runtime". The engineering value is role separation: an implementer with a fresh context per plan item, and a reviewer that sees the diff and never the implementer's reasoning.
- **Target Module / Layer:** `core/skills/orchestrate/SKILL.md` (new), `core/skills/catalog.json`, `install.sh`, `core/scripts/stack-context.sh`, `schema.json`, `harness.config.json`, `test/test_cli.sh`, `test/e2e/test_install_matrix.sh`, `README.md`, `docs/COMPATIBILITY.md`, `docs/ARCHITECTURE.md`, `docs/PROVENANCE.md`, `CHANGELOG.md`.

## 2. Requirements & Domain Floor Invariants

### Workflow contract
- [ ] `/harness-orchestrate <delta-spec-path>` accepts an approved delta spec whose section 3 carries a numbered Implementation Plan, and refuses to run without one, naming `/harness-implement` as the alternative.
- [ ] The workflow runs `harness spec verify <delta-spec-path>` as its entry gate and stops on a non-zero status.
- [ ] A runtime preflight verifies that subagent dispatch is available. When it is not, the workflow aborts with a diagnostic and names `/harness-implement`; it never degrades into single-context execution silently. This preflight is an agent-level gate stated in the skill, not a CLI-enforced one; the machine-enforced half of the Claude Code restriction is installer gating, and the spec claims nothing stronger.
- [ ] The workflow opens its run with `harness receipt start orchestrate` and `harness ledger start`, and closes it with `harness receipt finish`, reusing the AH-3 and AH-4 contracts unchanged.
- [ ] Plan items are dispatched strictly one at a time, in plan order. No two subagents are in flight at once.
- [ ] Each item dispatches an implementer with a fresh context, then a reviewer in a separate dispatch with a fresh context, and the reviewer receives the diff, the item, and `rules/floor.md` but never the implementer's reasoning or narrative.
- [ ] The implementer is required to follow the RED-GREEN-REFACTOR protocol and to run `harness qa test` before returning; it is forbidden from committing, pushing, or publishing.
- [ ] Review findings are classified Critical, Important, or Minor using the contract AH-4 established in `core/skills/review/SKILL.md`, and the AH-4 bounded three-round loop with mandatory adjudication applies per plan item.
- [ ] After the last item, the workflow runs `harness qa all` once and reports its real status; a failing gate is never reported as success.
- [ ] Before the final response the workflow runs `harness ledger rulings` and reproduces every line exhaustively, in recorded order.

### Dispatch contract
- [ ] Invariant: the orchestrator never edits production code, never writes tests, and never runs the fixes itself. Its only actions are dispatching, recording, and adjudicating. This is stated as an anti-rationalization row in the skill.
- [ ] Invariant: the orchestrator is the sole writer of the ledger. Subagents never call `harness ledger append`, so the ledger stays a single-voice record of what the orchestrator decided, and concurrent writes are impossible by construction.
- [ ] A subagent brief carries exactly seven fields: run identifier, delta spec path, plan item number, permitted files, acceptance criterion, test command, and prohibitions. The subagent inherits the repository and reads the spec from disk, so the brief stays short.
- [ ] A subagent returns a structured line of the form `ITEM <N> | STATUS pass|blocked | TESTS <command> <result> | FILES <list> | NOTES <one to three lines>`. A malformed return is re-dispatched exactly once; a second malformed return marks the item blocked.
- [ ] The orchestrator records every dispatch outcome in the ledger before dispatching the next role.

### Per-role model selection
- [ ] `harness.config.json` accepts `profiles.<profile>.orchestrate.models` with the string-valued keys `implementer` and `reviewer`, matching the two roles the workflow actually dispatches. Values are free-form strings, not an enumeration, because model identifiers age faster than this repository releases.
- [ ] `schema.json` describes that block, and an absent block is valid.
- [ ] `harness context --json` emits an `orchestrateModels` object resolved through the existing `get_profile_value` helper, falling back to the defaults documented in the skill. No new CLI subcommand is added.
- [ ] Invariant: the reviewer is always a separate dispatch from the implementer. Configuration selects which model fills a role and can never collapse the two roles into one dispatch.

### Runtime gating
- [ ] `core/skills/catalog.json` gains a sibling `runtimes` map keyed by public workflow name, and `orchestrate` declares `["claude"]`. A workflow absent from the map is installed into every runtime, so the existing three workflows need no entry.
- [ ] `schemaVersion` stays `1`. The field is additive, optional, and the catalog has no consumer outside this repository.
- [ ] `install_skill_surface` receives the destination's runtime label and installs a public workflow only when that runtime is permitted. Target installation maps `.gemini`, `.claude`, `.codex`, and `.agents`; global installation maps both Gemini directories to the same `gemini` label.
- [ ] Invariant: the managed-skill cleanup loop stays unconditional. Installation is filtered, removal is not, so a previously installed `harness-orchestrate` disappears from a now-disallowed destination on the next installation without any migration step.
- [ ] `require_skill_catalog` rejects an unknown runtime label and rejects a `runtimes` key that names a workflow absent from `public`.
- [ ] Runtime gating applies to public workflows only. Expert-mode internal primitives continue to reach all four destinations, and the documentation says so.

### Invariants
- [ ] Invariant: the change must not violate `rules/floor.md`.
- [ ] Invariant: the AH-3 receipt schema, the AH-4 ledger format, and the AH-4 ledger kinds are unchanged.
- [ ] Invariant: `/harness-implement`, `/harness-fix`, and `/harness-investigate` keep behaving identically under Antigravity, Claude Code, Codex, Cursor, and `.agents`. The five-runtime contract is not weakened; it is made explicit per skill.
- [ ] Invariant: installation stays idempotent, and no user-owned skill is removed.
- [ ] Invariant: shell changes pass `shellcheck -S warning` through `npm run lint`.
- [ ] Invariant: no subagent prompt, diff, or narrative is written into a receipt, and no ledger content leaves the local repository.

## 3. Implementation Plan
1. [ ] RED — extend `test/test_cli.sh` so the catalog assertion at its public-surface check requires the four public workflows and requires `orchestrate` to declare `runtimes` of `["claude"]`; add cases for target and global installation placing `harness-orchestrate` in `.claude/skills` and nowhere else, for cleanup of a stale copy in a disallowed destination, and for `harness context --json` emitting `orchestrateModels` with defaults and with a profile override.
2. [ ] GREEN — add the `runtimes` map to `core/skills/catalog.json`, thread a runtime label through `install_skill_surface` and both of its call sites, filter public workflow installation by that label, and extend `require_skill_catalog` with the two new validations.
3. [ ] GREEN — extend `schema.json` with the `orchestrate.models` block and `core/scripts/stack-context.sh` with the resolved `orchestrateModels` output.
4. [ ] Write `core/skills/orchestrate/SKILL.md` with the workflow contract, the seven-field brief, the structured return, the sole-writer ledger rule, the default implementer and reviewer model table, the anti-rationalization gate, and a state anchor consistent with the other workflows.
5. [ ] Make `test/e2e/test_install_matrix.sh` runtime-aware: pass the runtime into `verify_skill_surface`, compute the expected count from the workflows permitted for that runtime, assert the absence of gated workflows in the other destinations, and record the gating assertion in the evidence artifact.
6. [ ] Update `README.md`, `docs/COMPATIBILITY.md`, `docs/ARCHITECTURE.md`, and the `obra/superpowers` row of `docs/PROVENANCE.md` so it records the dispatch and model-selection method as adapted at `b36e082` instead of excluded; add the `CHANGELOG.md` entry under a new `2.1.0` heading and bump `package.json`.
7. [ ] Run `harness scan --diff`, `harness spec verify specs/delta-AH-7-orchestrate-dispatch.md`, the full suite, and the two-axis review.

## 4. Verification & QA
- **Automated Test Command:** `env -u STACK_PROFILE npm test && npm run lint && ./setup --verify`
- **Pre-flight Command:** `./bin/harness qa all`
- **Spec Verification:** `./bin/harness spec verify specs/delta-AH-7-orchestrate-dispatch.md`
- **Expected Outcome:** The new `test/test_cli.sh` cases pass and its existing groups stay green; `test/test_transaction_lib.sh` and `test/test_install_transaction.sh` stay green; the eight-cell compatibility matrix passes with the new per-runtime expectations and stays idempotent across two installer executions; `shellcheck -S warning` is clean; and `./setup --verify` succeeds.

## 5. Non-Goals
- Parallel dispatch. Two subagents editing one working tree is a race. The condition that would unblock it is per-subagent worktree isolation, and that is a separate proposal.
- A worktree per subagent, and the conflict resolution and integration work that isolation implies.
- Porting the `superpowers` prompt templates or its `sdd-workspace`, `task-brief`, and `review-package` scripts. Only the method is adapted, so no third-party notice obligation is created.
- Extending orchestration to `/harness-fix` or `/harness-investigate`.
- Changing the AH-3 receipt schema, the AH-4 ledger format, or the AH-4 bounded loop.
- Letting the orchestrator commit, push, open a pull request, or change any external system.
- Enumerating or pinning model identifiers in `schema.json`.
- A third skill-surface mode. Gating is a property of a workflow in the catalog, not a new installation flag.
