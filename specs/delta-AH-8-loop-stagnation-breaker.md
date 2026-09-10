# Delta Spec: AH-8 — loop-stagnation-breaker

## 1. Intent & Context
- **Issue / Ticket:** AH-8
- **Summary:** AH-4 gave `/harness-implement` a bounded review loop with a hard cap of three rounds, but the cap is the *only* exit. A loop whose verification fails the same way three times in a row spends its entire budget re-deriving one failure, then adjudicates from a position no better than round one. This delta adds the missing second exit: a deterministic failure **signature**, and a breaker that stops the loop when consecutive rounds fail equivalently. The method is adapted from the `normalize_failure` / `evaluate_breaker` pair in [`codejunkie99/agentic-stack-desktop`](https://github.com/codejunkie99/agentic-stack-desktop), which scrubs volatile detail out of verifier output before comparing failures. Its surrounding machinery — the Python loop runner, autonomy levels, capability envelopes, and path constraints — is deliberately excluded here.
- **Target Module / Layer:** `core/scripts/stack-ledger.sh`, `bin/harness`, `core/scripts/stack-completion.sh`, `core/skills/implement/SKILL.md`, `schema.json`, `test/test_cli.sh`, `docs/PROVENANCE.md`, `docs/ARCHITECTURE.md`, `README.md`, `CHANGELOG.md`, `package.json`.

## 2. Requirements & Domain Floor Invariants

### Failure signature
- [x] `harness ledger signature` reads failure text from **stdin** and prints a 12-character lowercase hex signature followed by a newline. It takes no run ID, touches no ledger, and is stateless, so it is directly testable.
- [x] The normalization ruleset is applied in this fixed order before hashing: ISO-8601 timestamps become `<timestamp>`; absolute directory prefixes become `<path>/`; `:<line>` and `:<line>:<column>` suffixes become `:<line>`; runs of six or more digits become `<id>`; every run of whitespace collapses to one space; leading and trailing whitespace is trimmed. **Amended during implementation.** As written, this rule began by rewriting the target repository root to a `<target>` token of its own. A live end-to-end run showed that makes one file sign two ways — `<target>/src/widget.py` from the signing checkout and `<path>/widget.py` from any other — which contradicts this delta's own claim that failures differing only in absolute path sign identically. The root rule was dropped rather than reordered: under any order that fixes the divergence, the absolute-directory rule consumes the root first and the root rule becomes unreachable. Its only unique reach was a repository root mentioned with no file after it, which is rare in verifier output and not worth the contradiction. Removing it also removed the sed-pattern escaping the root required, and the whole class of quoting hazards with it.
- [x] Signatures are checkout-independent for paths that contain no whitespace: the same failure signs identically whether it was captured in this worktree, another clone, or a CI runner's temporary directory. A repository path containing a space is the documented limit of a whitespace-delimited path rule, and is not normalized.
- [x] The digest is produced by `git hash-object --stdin` and truncated to its first 12 characters. Git is already a hard dependency of every script in `core/scripts`, so this adds none, and it avoids the `shasum` versus `sha256sum` split between the two CI runners.
- [x] Normalization and hashing run as a single stream pipeline. Verifier output is never assigned to a shell variable, so a multi-megabyte test log is bounded by pipe buffers rather than by process memory.
- [x] Empty stdin, or stdin that normalizes to the empty string, exits non-zero with a diagnostic and prints no signature. A failure with no content is not a signature, and treating it as one would let two unrelated empty captures read as stagnation.

### Breaker
- [x] `harness ledger failure <run_id> [label]` reads failure text from stdin, computes its signature, appends one ledger line, and prints its decision: `continue` on exit status `0`, or `stagnant` on exit status `3`. Both channels always agree, so a caller that reads only the word and a caller that reads only the status reach the same conclusion.
- [x] Exit status `3` is reserved for the stagnation decision. Every other non-zero status is an error, so a caller can distinguish "the loop must stop" from "the command did not run".
- [x] `failure` joins `phase`, `ruling`, `deferred`, `parked`, and `complete` as an accepted ledger kind. Its line body is `sig:<signature>` alone, or `sig:<signature> — <label>` when a label is given.
- [x] The optional `label` is a single line of at most 200 bytes, validated on the same terms as existing ledger text. It carries the agent's own words about the round; it never carries verifier output.
- [x] The decision is stagnant when the last `<threshold>` `failure` lines of that run all carry the same signature, and the run has at least `<threshold>` of them. Any intervening `phase`, `ruling`, `deferred`, `parked`, or `complete` line is ignored by the comparison, because a round that records progress does not reset the failure history.
- [x] `profiles.<profile>.loop.stagnationThreshold` configures the threshold, defaults to `2`, and is described in `schema.json`. A value below `2` or a non-integer is rejected with a diagnostic rather than silently clamped.
- [x] The threshold is read through the existing `get_profile_value` helper, which already degrades to its default argument when `jq` is absent. `harness ledger` therefore stays usable without `jq`, exactly as AH-4 left it.

### Workflow contract
- [x] Phase 7 of `/harness-implement` pipes the verification output of every failed round through `harness ledger failure "$RUN_ID"` before deciding whether to open the next round.
- [x] A `stagnant` decision ends the loop immediately and moves to the AH-4 adjudication gate with the rounds it has, even when rounds remain under the cap. The adjudication gate itself is unchanged: every open finding is still parked with a recorded ruling or classified load-bearing, and a load-bearing finding still ends the run `blocked`.
- [x] The three-round cap is unchanged. Stagnation can only end the loop earlier than the cap; it can never extend it, and reaching the cap without stagnation behaves exactly as AH-4 specified.
- [x] `core/skills/implement/SKILL.md` gains an anti-rationalization row for the one rationalization this mechanism invites: that a signature match is a coincidence worth one more round.
- [x] The phase 7 state anchor carries the current signature so a compacted context can see the repetition it is inside.

### Invariants
- [x] Invariant: the change must not violate `rules/floor.md`.
- [x] Invariant: verifier output is never written to a ledger, a receipt, or any other artifact. Only its 12-character signature and the agent's own label are recorded, so the ledger keeps the evidence-free property AH-3 and AH-4 established.
- [x] Invariant: `harness ledger rulings` output is unchanged. It filters on `$2 == "ruling" || $2 == "parked"`, and a `failure` line matches neither.
- [x] Invariant: the AH-3 receipt schema is unchanged. No new phase token, outcome, or field is added, and stagnation is not a receipt event.
- [x] Invariant: the ledger stays append-only. The breaker reads prior lines to decide; it never rewrites or deletes one.
- [x] Invariant: no requirement depends on subagent dispatch, per-role model selection, or any other single-runtime primitive. Phase 7 behaves identically under Antigravity, Claude Code, Codex, Cursor, and `.agents`.
- [x] Invariant: the normalization pipeline uses only POSIX-portable `sed -E` and `tr` constructs, with no GNU-only escapes such as `\b`, `\+`, or `\d`. It must produce byte-identical signatures on the macOS and Ubuntu CI runners for the same input, and a test asserts that against a fixed corpus rather than trusting the pipeline by inspection.
- [x] Invariant: no new runtime dependency. Bash, Git, `sed`, and `tr` only; `jq` stays optional.
- [x] Invariant: `core/scripts/stack-ledger.sh` passes `shellcheck -S warning` through `npm run lint`.
- [x] Invariant: no Apache-2.0 source, test, or documentation text is copied from the upstream project. The reuse is the method, so it creates no `THIRD_PARTY_NOTICES.md` entry under the licensing policy in `docs/PROVENANCE.md`.

## 3. Implementation Plan
1. [x] RED — extend `test/test_cli.sh` with cases for: signature determinism across two invocations of the same input; signature equality for two failures differing only in timestamp, absolute path, line and column, and long numeric ID; signature inequality for two materially different failures; rejection of empty and whitespace-only stdin; the fixed-corpus cross-runner assertion; `failure` line format with and without a label; label validation; `continue` on the first failure and on two differing failures; `stagnant` with exit `3` on two identical failures; stagnation across an intervening `phase` line; threshold override through `profiles.harness.loop.stagnationThreshold`; rejection of a threshold below `2`; and `rulings` output unaffected by `failure` lines.
2. [x] GREEN — implement `signature` and `failure` in `core/scripts/stack-ledger.sh`, reusing `validate_run_id` and `require_ledger`, and extending `validate_kind` with `failure`. **Delivered without reusing `validate_text` on the failure line:** a 12-character signature plus a label capped at 200 bytes cannot reach `MAX_TEXT_BYTES`, so the check could never fail and was removed as dead defensive code.
3. [x] Wire both actions into `bin/harness` help text. **The completion half was a no-op:** `core/scripts/stack-completion.sh` enumerates top-level commands only and describes no subaction of `ledger`, `receipt`, `spec`, or `qa`, so adding action-level completion for `ledger` alone would have been inconsistent scope.
4. [x] Extend `schema.json` with the `profiles.<profile>.loop.stagnationThreshold` block, described as optional with a default of `2`.
5. [x] Amend the phase 7 contract, the anti-rationalization table, and the state anchor in `core/skills/implement/SKILL.md`.
6. [x] Add the upstream row and its Upstream Drift Audit entry to `docs/PROVENANCE.md` at snapshot [`210a199`](https://github.com/codejunkie99/agentic-stack-desktop/tree/210a199ce006ccbd76cae0e663c6ebf99381efb9), record the mechanism in `README.md`, add the `CHANGELOG.md` entry, and bump `package.json` to the next unreleased minor. **`docs/ARCHITECTURE.md` was left unchanged:** its diagram carries no ledger node, AH-4 added none when it introduced the ledger, and adding one for the breaker alone would misrepresent the diagram's altitude.
7. [x] Run `npm run lint`, `harness scan --diff`, `harness spec verify specs/delta-AH-8-loop-stagnation-breaker.md`, the full suite, and the two-axis review.

## 4. Verification & QA
- **Automated Test Command:** `env -u STACK_PROFILE npm test && npm run lint && ./setup --verify`
- **Pre-flight Command:** `./bin/harness qa all`
- **Spec Verification:** `./bin/harness spec verify specs/delta-AH-8-loop-stagnation-breaker.md`
- **Expected Outcome:** The new `test/test_cli.sh` cases pass and its existing groups stay green; `test/test_transaction_lib.sh` and `test/test_install_transaction.sh` stay green; `shellcheck -S warning` is clean; `./setup --verify` succeeds; and CI passes on both the macOS and Ubuntu runners, which is what actually proves the portability invariant.

## 5. Non-Goals
- Extending the breaker to `/harness-fix`, `/harness-investigate`, or the `/harness-orchestrate` surface proposed by AH-7. AH-4 confined the bounded loop to `/harness-implement`, and this delta keeps that boundary.
- Changing the three-round cap, or making it configurable. The cap is a judgement about when a loop has become structural; the threshold is a judgement about when two failures are the same. They are separate knobs and only the second one is introduced here.
- Adopting the rest of the upstream loop design: its `L1`/`L2`/`L3` autonomy levels, its `workspace_write`/`network_read`/`external_write` capability envelope, its `approval` gates, its `deny_paths` and `max_changed_files` constraints, its worktree ownership model, or its declarative adapter manifests. Each is a separate proposal with its own justification, and bundling them would make this diff unreviewable.
- Copying upstream Python, tests, or documentation. Only the normalization-then-compare method is adapted, in Bash, against this repository's own ledger.
- Recording verifier output, diffs, prompts, durations, or token counts anywhere. The signature exists precisely so that comparing failures does not require keeping them.
- Detecting stagnation across runs, or persisting signatures beyond the ledger of one run.
- A read-only `harness ledger stagnant <run_id>` query. `failure` already returns the decision at the only moment a caller needs it, and a second entry point would be a second place for the two to disagree.

## 6. Open Questions
- **Release numbering — resolved.** AH-7 landed as `2.1.0` before this delta was implemented, so AH-8 was cut as `2.2.0`.
- **Default threshold.** `2` is taken from upstream and is the strongest useful value against a three-round cap: it saves round three whenever rounds one and two fail equivalently. If it proves to fire on genuinely progressing rounds that happen to end at the same assertion, the correction is to sharpen the normalization ruleset, not to raise the default to `3` — a threshold of `3` under a cap of `3` can never fire before the cap and would make the mechanism dead code.
