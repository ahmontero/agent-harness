# Delta Spec: AH-16 — digest-interrupted-write

## 1. Intent & Context
- **Issue / Ticket:** AH-16
- **Module:** surface
- **Summary:** Installation aborts at random on macOS with `core/scripts/lib/surface.sh: line 77: printf: write error: Interrupted system call`, rolls back, and reports every published skill name as an occupied path. It has been observed on `main` at `7ea3705` and on two branches, landing in a different matrix cell each time, so a red run carries no information about the change that produced it. The three digest functions write to a pipe with a shell builtin while child processes are being reaped — `jq` in a process substitution, `basename` per reference, `cat` per file — and bash on macOS does not restart a write the arriving `SIGCHLD` interrupts. Writes to a regular file are not interruptible, so routing the bytes through one removes the race rather than narrowing it.
- **Target Module / Layer:** `core/scripts/lib/surface.sh`, `test/test_cli.sh`, `CHANGELOG.md`, `README.md`, `package.json`.

## 2. Requirements & Domain Floor Invariants
- [x] Requirement 1: No shell builtin writes into a pipe in `surface_digest_stream`, `surface_source_digest`, or `surface_installed_digest`.
- [x] Requirement 2: The bytes fed to `git hash-object` are unchanged, so every digest recorded by an existing surface manifest still matches and no installed surface is reported as drifted by this change alone.
- [x] Requirement 3: File content reaches the hash through a regular file rather than a shell variable. Command substitution strips trailing newlines and truncates at a NUL, either of which would silently change a digest.
- [x] Requirement 4: A test pins the digest contract — the source digest of a workflow equals the installed digest of the bundle published from it, and both equal a digest computed by an explicit independent command — so a later refactor cannot change the bytes unnoticed.
- [x] Invariant: Must not violate `rules/floor.md`. A digest is an identity claim; a change that altered it silently would make every drift report wrong at once.

## 3. Implementation Plan
1. [x] Add failing coverage to `test/test_cli.sh` pinning the digest contract and its determinism across repeated calls.
2. [x] Accumulate the listing in a shell variable in `surface_source_digest` and `surface_installed_digest`, and feed `sort` through a here-string, so no builtin writes to a pipe while children are reaped.
3. [x] Materialize the hashed payload in a regular file in `surface_digest_stream`, preserving the bytes exactly.
4. [x] Prove the digests are unchanged by comparing every workflow and installed bundle digest before and after.
5. [x] Run `harness qa all` and the full suite.

## 4. Verification & QA
- **Automated Test Command:** `env -u STACK_PROFILE npm test`
- **Expected Outcome:** Green suite with zero regressions, including the new assertions in group 37, and a byte-identical digest for every workflow and installed bundle compared with the previous implementation.
