# Delta Spec: NAMESPACE — Agent skill names

## 1. Intent & Context
- **Issue / Ticket:** NAMESPACE
- **Summary:** Publish every Agent Harness workflow and expert skill under the `harness-` namespace so generic names do not collide with user or third-party skills in Gemini, Claude, Codex, or `.agents` runtimes.
- **Target Module / Layer:** `core/skills/catalog.json`, canonical skill metadata, `install.sh`, installation tests, and public documentation.

## 2. Requirements & Domain Floor Invariants
- [x] The catalog declares `harness` as the single publication namespace.
- [x] Default installations expose exactly `harness-implement`, `harness-fix`, and `harness-investigate` in every supported runtime.
- [x] Expert installations expose every supported primitive as `harness-<name>` and never publish an unprefixed Agent Harness skill.
- [x] Installed directory names and each installed `SKILL.md` frontmatter `name` agree.
- [x] Reinstallation removes legacy unprefixed Agent Harness-managed paths while preserving unrelated user-owned paths.
- [x] Installation remains idempotent across `.gemini`, `.claude`, `.codex`, and `.agents` targets.
- [x] CLI subcommands and receipt workflow tokens remain unchanged.
- [x] Invariant: required gates fail closed, shell behavior remains portable across supported macOS and Linux runners, and no user-owned files are deleted.

### Non-goals
- Rename `harness` CLI subcommands such as `harness qa` or receipt workflow tokens.
- Rename private reference filenames bundled inside composite workflows.
- Add runtime-specific naming conventions.

## 3. Implementation Plan
1. [x] Add failing tests for namespaced directories, matching frontmatter, legacy cleanup, and user-content preservation.
2. [x] Add the canonical namespace to the catalog and apply it at the installer publication boundary.
3. [x] Namespace canonical skill metadata and user-facing skill references.
4. [x] Update documentation and migrate the repository's local runtime surfaces.
5. [x] Run scan, CLI tests, installation matrix, and spec verification.

## 4. Verification & QA
- **Automated Test Command:** `npm test`
- **Pre-flight Command:** `./bin/harness qa all`
- **Spec Verification:** `./bin/harness spec verify specs/delta-NAMESPACE-skill-names.md`
- **Expected Outcome:** Every supported runtime exposes only `harness-*` Agent Harness skills, old managed aliases disappear safely, user-owned skills survive, and all existing behavior remains green.
