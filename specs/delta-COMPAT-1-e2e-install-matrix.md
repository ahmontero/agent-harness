# Delta Spec: COMPAT-1 — e2e-install-matrix

## 1. Intent & Context
- **Issue / Ticket:** COMPAT-1
- **Summary:** Turn the repository's multi-harness installation claim into public, repeatable evidence. A dedicated black-box runner will exercise every supported installation scope and skill-surface mode, while CI will execute each cell independently on Ubuntu and macOS and retain a machine-readable result.
- **Target Module / Layer:** `test/e2e/`, `.github/workflows/`, `docs/COMPATIBILITY.md`, `test/test_cli.sh`, and `README.md`.

## 2. Requirements & Domain Floor Invariants
- [x] **REQ-COMPAT-1:** Provide an executable black-box installer test accepting `--scope target|global`, `--mode default|expert`, and `--report <path>`.
- [x] **REQ-COMPAT-2:** Every matrix cell must run in isolated temporary `HOME` and target directories, execute installation twice, and prove that the managed installation is idempotent.
- [x] **REQ-COMPAT-3:** Target cells must verify the `.gemini`, `.claude`, `.codex`, `.agents`, and `.cursor` contracts; global cells must verify the four supported global skill locations and CLI links.
- [x] **REQ-COMPAT-4:** Default mode must expose only the three public workflows; expert mode must also expose every supported internal primitive; neither mode may restore removed skills.
- [x] **REQ-COMPAT-5:** The runner must preserve an unmanaged user skill across repeated installation and emit a versioned JSON result containing OS, scope, mode, status, and verified runtime contracts.
- [x] **REQ-COMPAT-6:** GitHub Actions must execute the complete `2 OS × 2 scopes × 2 modes` matrix and upload each JSON result as an artifact.
- [x] **REQ-COMPAT-7:** `docs/COMPATIBILITY.md` must explain the verified contract, evidence boundaries, reproduction commands, and the distinction between filesystem compatibility and launching proprietary agent runtimes.
- [x] **Invariant:** Required failures return non-zero; success must never be printed after a failed assertion.
- [x] **Invariant:** Tests must be portable to the Bash version supplied by supported macOS and Linux runners.
- [x] **Invariant:** Tests must not write to the developer's real home directory or require network access.

### Non-goals

- Launching Claude Code, Codex, Cursor, or Antigravity in CI.
- Claiming Windows support.
- Testing remote package registries or the published npm tarball.
- Changing installer behavior unless the black-box matrix exposes a defect.

## 3. Implementation Plan
1. [x] Add a contract assertion to `test/test_cli.sh` and verify RED while the E2E runner is absent.
2. [x] Implement `test/e2e/test_install_matrix.sh` with isolated fixtures, assertions, idempotence checks, and JSON output.
3. [x] Add `.github/workflows/compatibility.yml` with the eight independent matrix cells and uploaded evidence artifacts.
4. [x] Document the compatibility contract and link it from the README.
5. [x] Run the E2E matrix locally, the full regression suite, setup verification, scan, and two-axis review.

## 4. Verification & QA
- **Focused RED/GREEN Command:** `bash test/test_cli.sh`
- **Matrix Command:** `bash test/e2e/test_install_matrix.sh`
- **Required Gates:** `./setup --verify`, `./bin/harness scan --diff`, and `bash test/test_cli.sh`
- **Expected Outcome:** Eight passing compatibility cells across CI, each with a valid JSON evidence artifact, plus zero regressions in the existing suite.
