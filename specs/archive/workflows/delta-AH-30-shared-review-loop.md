# Delta Spec: AH-30 — shared-review-loop

## 1. Intent & Context
- **Issue / Ticket:** AH-30
- **Module:** workflows
- **Summary:** The Bounded Review Loop is the mechanism that makes a review gate terminate without dropping a finding, and only `/harness-implement` has all of it. `/harness-orchestrate` carries a second copy that has already fallen behind. `/harness-fix` has a review phase and no bound on it at all, and no ledger to survive a compacted context. This delta moves the loop into one primitive the workflows reference, gives `fix` the same discipline `implement` has, and gives `investigate` a ledger without a loop it has no use for.
- **Target Module / Layer:** `core/skills/loop/SKILL.md` (new), `core/skills/catalog.json`, `core/skills/{implement,fix,orchestrate,investigate}/SKILL.md`, `README.md`, `test/test_cli.sh`.

### The drift is not hypothetical

`implement` and `orchestrate` hold two hand-maintained copies of the same protocol, and they differ in twelve lines. One of those differences is the stagnation breaker: `orchestrate` never learned to sign a failed round, so a dispatched run that keeps failing the same way spends all three rounds re-deriving one failure before it adjudicates. That is the copy falling behind in exactly the way a second copy does, and nothing reported it — it took reading both to notice.

### What `fix` is missing and why it matters

`/harness-fix` phase 7 says to apply `references/review.md` and hand off. `review.md` classifies findings Critical, Important and Minor "because the bounded review loop in `/harness-implement` consumes it" — a protocol `fix` does not have. So a fix whose review keeps finding problems has no cap, no signature, no adjudication and no rulings to reproduce: the agent decides on its own when to stop and never has to say what it decided. That is the failure mode the loop exists to close, left open in the workflow most likely to meet it.

### Why `investigate` gets a ledger and not a loop

`investigate` is read-only and terminates at a recommendation. It has no correction to re-review, so a bounded loop would be a gate over nothing. What it does have is length: an investigation can outlive its own context, and re-deriving evidence after a compaction is the cost the ledger exists to remove. It gets `harness ledger start` and phase lines, and nothing about rounds, rulings or adjudication.

## 2. Requirements & Domain Floor Invariants
- [ ] R1: The Bounded Review Loop exists once, as `core/skills/loop/SKILL.md`, published into the bundles of `implement`, `fix` and `orchestrate` as `references/loop.md` through the catalog the installer already uses for references.
- [ ] R2: No workflow restates the loop's rules inline. A workflow names when to enter it and what its own round and ledger lines look like; the rules of the loop itself live in one file.
- [ ] R3: The shared loop carries every rule both current copies have between them, including the stagnation signature `orchestrate` lacks. Nothing is lost in the merge: the union, not the intersection.
- [ ] R4: `/harness-fix` opens a receipt **and** a ledger, runs the bounded loop in its review phase, and reproduces `harness ledger rulings` before its final response.
- [ ] R5: `/harness-investigate` opens a ledger and records phase outcomes in it. It gains no loop, no rounds and no adjudication.
- [ ] R6: `/harness-orchestrate` signs each failed round with `harness ledger failure`, which it does not do today.
- [ ] R7: The README stops saying the ledger belongs to `/harness-implement` and describes which workflows open one and which run the loop.
- [ ] R8: A test asserts the loop is not restated: no workflow file may contain the loop's own rules, and every workflow that runs it must reference it. The drift this delta removes cannot come back by hand-editing one copy, because there is only one.
- [ ] Invariant: Must not violate `rules/floor.md`. Invariant 3 in particular — a workflow that advertises a bounded review must have one, which is the claim `fix` makes today through `review.md` and does not honour.

### Non-goals
- Changing `harness ledger` or `harness receipt`. Both already accept every kind and phase this needs; the gap is entirely in the protocols, not the CLI.
- A loop for `investigate`. Stated above and deliberate.
- Rewriting `review.md`. Its severity classification is already correct and is what the loop consumes; it only stops being a promise `fix` cannot keep.

## 3. Implementation Plan
1. [ ] RED — assert that `fix` and `investigate` open a ledger, that `fix` and `orchestrate` reference the shared loop and sign failed rounds, and that no workflow restates the loop's rules inline.
2. [ ] Write `core/skills/loop/SKILL.md` as the union of the two current copies, phrased so a dispatched round and an in-context round are both described by it.
3. [ ] Add `loop` to the catalog's `internal` list and to the reference list of `implement`, `fix` and `orchestrate`.
4. [ ] Replace the inline loop in `implement` and `orchestrate` with a reference, keeping each workflow's own round and ledger line formats.
5. [ ] Give `fix` the receipt-and-ledger opening, the loop reference in phase 7, and the rulings reproduction.
6. [ ] Give `investigate` a ledger opening and phase lines, and nothing else.
7. [ ] Update the README's ledger section, then run `harness qa all`.

## 4. Verification & QA
- **Automated Test Command:** `bash test/test_cli.sh`
- **Expected Outcome:** The new assertions pass; groups 2, 2b, 20, 36 and 37 stay green, which is what proves the catalog change is coherent — they already assert skill frontmatter, the public workflow contract, surface manifests, trigger coverage and bundle digests. `harness qa all` exits 0, and an installed bundle carries `references/loop.md` for the three workflows that run it and not for the one that does not.
