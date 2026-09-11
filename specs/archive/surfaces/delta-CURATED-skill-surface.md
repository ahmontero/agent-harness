# Delta Spec: CURATED — skill surface

## 1. Intent & Context
- **Issue / Ticket:** CURATED
- **Summary:** Reduce the default user-facing skill surface from nineteen independent commands to three intent-level workflows: `implement`, `fix`, and `investigate`. Preserve the existing primitive protocols as private workflow references and provide an explicit expert installation mode for users who want direct access.
- **Target Module / Layer:** `install.sh`, `core/skills/`, `test/test_cli.sh`, `README.md`, and `docs/ARCHITECTURE.md`.

## 2. Requirements & Domain Floor Invariants
- [x] A default target or global installation exposes exactly `implement`, `fix`, and `investigate` in every supported runtime skill directory.
- [x] Each public workflow includes the private protocol references it needs and no longer depends on user-invocable primitive skills.
- [x] `--expert` installs every supported public workflow and primitive skill except the removed `ship` skill.
- [x] Re-running a curated installation removes only stale Agent Harness-managed skill links and preserves unrelated user-owned skills.
- [x] The `ship` skill is removed; explicit commit, push, and PR operations remain available through the CLI and direct user authorization.
- [x] Existing CLI commands and execution receipt contracts remain backward compatible.
- [x] Installation remains idempotent across `.gemini`, `.claude`, `.codex`, and `.agents` targets.
- [x] Invariant: required gates fail closed, shell behavior remains portable across supported macOS and Linux runners, and no user-owned files are deleted.

### Non-goals
- Add platform-specific hidden-skill metadata.
- Rename the existing CLI commands.
- Automatically commit, push, or open pull requests.
- Introduce a plugin system or a general-purpose package builder.

## 3. Implementation Plan
1. [x] Add failing installation tests for the curated surface, embedded references, expert mode, safe cleanup, and idempotence.
2. [x] Add a canonical skill catalog and a small installer seam that builds public workflow bundles from canonical primitive skill documents.
3. [x] Update the public workflows to load private reference documents instead of invoking slash commands.
4. [x] Remove `ship`, update help and documentation, and preserve operational publishing through the CLI.
5. [x] Simplify the installer changes and run scan, full QA, and two-axis review.

## 4. Verification & QA
- **Automated Test Command:** `npm test`
- **Pre-flight Command:** `./bin/harness qa all`
- **Spec Verification:** `./bin/harness spec verify specs/delta-CURATED-skill-surface.md`
- **Expected Outcome:** New curated installations expose only three workflows, expert installations expose the supported advanced set, public workflows retain every required protocol reference, migration preserves user-owned skills, and all existing tests remain green.
