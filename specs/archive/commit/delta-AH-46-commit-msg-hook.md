# Delta Spec: AH-46 — commit-msg-hook

## 1. Intent & Context
- **Issue / Ticket:** AH-46
- **Module:** commit
- **Summary:** `harness commit check` enforces Conventional Commits, the branch's issue key, and forbidden trailers — and has no enforcement point until `harness ship` or CI, by which time the commit is in the history and the only remedy is rewriting it. The scanner ships a `pre-commit` hook; the message validator ships none. AH-42 is the proof: `commit build` wrote a non-conforming commit and the disagreement surfaced at `ship`.
- **Target Module / Layer:** `core/scripts/stack-commit.sh`, `core/scripts/lib/git.sh`, `core/scripts/stack-doctor.sh`, `core/scripts/stack-uninstall.sh`, `test/test_cli.sh`

## 2. Requirements & Domain Floor Invariants
- [ ] R1: `harness commit --install-hook [--force]` installs a `commit-msg` hook, carrying a marker, with the same foreign-hook protection and backup behaviour `harness scan --install-hook` already has.
- [ ] R2: The hook rejects a message `harness commit check` would reject, before the commit exists.
- [ ] R3: `harness commit check --message-file <path>` validates a message file, and shares one implementation with the revision path. Two copies of three rules is the divergence this repository keeps closing.
- [ ] R4: The hook does not fire on a message the project did not author: a merge, a revert, or a `fixup!`/`squash!` subject. This repository's own history is mostly merge commits, so a hook that rejected them would be uninstalled the first time someone merged.
- [ ] R5: Comment lines are stripped before validation. Git passes the hook the raw file including its `#` template, and a forbidden trailer named in a comment is not a trailer the commit carries.
- [ ] R6: `harness doctor` reports it, and `harness uninstall` removes it, exactly as both already do for the `pre-commit` hook. A second managed hook that the diagnostic ignores and the uninstaller leaves behind is the asymmetry AH-43 was about.
- [ ] Invariant: Must not violate `rules/floor.md` — 1 (gates fail closed), 3 (claims are executable), 6 (changes stay scoped).

**Non-goals.** The hook does not rewrite or repair a message; `harness commit build` is how a conforming one is produced. It does not run the landmine scanner — that is `pre-commit`'s job and duplicating it would double every commit's cost. `harness init --with-hook` continues to mean the scanner's hook; changing what an existing flag installs would alter behaviour nobody asked to change.

## 3. Implementation Plan
1. [ ] RED: a repository with the hook installed rejects a non-conforming message and accepts a conforming one; a merge still commits.
2. [ ] Extract message validation so the revision path and `--message-file` share it.
3. [ ] Add `--install-hook`/`--force` to `harness commit`, reusing the marker and backup logic in `lib/git.sh`.
4. [ ] Report it in `doctor`; remove it in `uninstall`.
5. [ ] Run `harness scan --branch`, `bash test/test_cli.sh`, ShellCheck and `./setup --verify`.

## 4. Verification & QA
- **Automated Test Command:** `bash test/test_cli.sh --group 57`
- **Expected Outcome:** Green suite with zero regressions; a non-conforming `git commit` fails with the message validator's own diagnosis, and `git merge` still succeeds.
