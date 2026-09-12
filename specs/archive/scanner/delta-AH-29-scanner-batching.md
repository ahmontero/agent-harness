# Delta Spec: AH-29 — scanner-batching

## 1. Intent & Context
- **Issue / Ticket:** AH-29
- **Module:** scanner
- **Summary:** The landmine scanner spawns one `grep` per `(rule, file)` pair. Measured on a 500-file repository: 6.6s with four rules, 13.2s with eight — exactly linear in the product, and about 3.3ms of process startup per invocation. AH-28 doubled the rule count and therefore the cost, and recorded that as debt. This delta inverts the loops so a rule is applied in one `grep` invocation over the files it is scoped to, not one per file.
- **Target Module / Layer:** `core/scripts/stack-scan.sh`, `test/test_cli.sh`.

### What the time is actually spent on

At 500 files and 8 rules the scan runs 4000 `grep` processes and roughly 80 `jq` ones. Process startup dominates: the greps are about 94% of the wall clock. Collapsing the `jq` reads is worth about 6% and is done here because it is nearly free, but it is not the point of the delta.

### Why the jq reads cannot become one `@tsv` call

`stack-scan.sh` already documents the trap: `@tsv` escapes backslashes, which turns every `\(` in a rule into a literal backslash followed by an unbalanced group, so a pattern that compiles would be rejected by its own validator. The fields are hoisted out of the rule loop as one `jq -r` per field across all rules, which preserves the raw values.

## 2. Requirements & Domain Floor Invariants
- [x] R1: A content rule is applied in one `grep` invocation per `xargs` chunk, not one per file. The number of `grep` processes a scan runs is a function of the rule count, not of the rule count times the file count.
- [x] R2: The findings are unchanged. For the same input the scanner reports the same rule IDs, the same repository-relative paths, the same line numbers, the same grouping of matches under a file, and the same order. This delta is an optimization and must be invisible in the output.
- [x] R3: `--staged` still reports repository paths and the line numbers of the staged content. Files are read from temporary blobs there, so a batched `grep` prints the blob path and it has to be mapped back before anything is reported. A finding that cites a temporary path is worse than a slow scan.
- [x] R4: A file list larger than `ARG_MAX` is handled, and the suite covers it. Without chunking grep is not merely given fewer files — it is never invoked, its error is swallowed by the existing `2>/dev/null`, and the scan reports "passed with 0 errors" over a repository carrying violations. The fixture reaches 1.9MB of paths with three thousand files by nesting long directory names, and asserts its own size so it cannot quietly stop exercising the chunked path. 5000 paths of average length exceed the 256KB limit on macOS, so the invocation is chunked with `xargs -0` rather than passed as one argument vector.
- [x] R5: `excludePaths` and `fileExtensions` still scope a rule, applied while building that rule's file list rather than inside the loop that no longer exists.
- [x] R6: Per-line `harness-ignore:` suppression still applies to every match.
- [x] R7: The invariant in R1 is asserted deterministically. A wall-clock bound flakes on a shared CI runner; a `grep` shim earlier on `PATH` that counts its own invocations does not, and it measures the property the delta is actually about.
- [x] Invariant: Must not violate `rules/floor.md`. Invariant 4 in particular — `xargs -0`, `grep -H` and `grep -I` must behave the same on the BSD and GNU tools the two CI runners provide.

### Non-goals
- The per-match `sed` in `line_is_suppressed`. It is O(matches), not O(files), and a scan with many matches is failing anyway.
- Paths containing newlines. `git diff --name-only` quotes them and the existing `while IFS= read -r` loop already mishandles them. That is a pre-existing defect with its own reproduction, and mixing it in would make this diff impossible to review as an optimization.
- Parallelism. One `grep` per rule is enough to remove the bottleneck; a job pool would add failure modes to a gate whose whole value is being trustworthy.

## 3. Implementation Plan
1. [x] RED — add a scanner group asserting the `grep` process count stays proportional to the rule count as the file count grows, using a counting shim on `PATH`.
2. [x] RED — capture the current scanner output over a fixture exercising a content rule, a `pathPattern` rule, `fileExtensions`, `excludePaths` and a suppressed line, and assert the new implementation reproduces it exactly.
3. [~] Hoist the per-rule `jq` field reads out of the rule loop — **dropped**. Reading each field into an array desynchronizes every array when a rule's `name` or `message` contains a newline, and the `@tsv` form that would avoid the loop is the one this file already forbids for escaping backslashes. It is 6% of the wall clock against a correctness hazard, and R1 does not need it: the rule loop stays, only the file loop inside it goes.
4. [x] Build, per rule, the list of files it is scoped to, as parallel repository-path and source-path arrays.
5. [x] Replace the per-file `grep` with one `xargs -0 grep -HEnI` per rule, regrouping matches by file so the reported shape is unchanged.
6. [x] Map source paths back to repository paths so `--staged` reports what R3 requires.
7. [x] Apply the same batching to `pathPattern` rules, which match names rather than content.
8. [x] Re-measure the 500-file fixture and record the before and after in `CHANGELOG.md`.

## 4. Verification & QA
- **Automated Test Command:** `bash test/test_cli.sh`
- **Expected Outcome:** The new group passes; scanner groups 5, 17, 19, 31, 33, 34 and 43 stay green, which is what makes R2 credible — they already assert staged-versus-working-tree fidelity, branch ranges, rule validation, path scoping and suppression. `harness qa all` exits 0, and the 500-file fixture scans in a fraction of the 13.2s it takes today.
