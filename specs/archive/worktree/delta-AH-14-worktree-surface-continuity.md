# Delta Spec: AH-14 — worktree-surface-continuity

## 1. Intent & Context
- **Issue / Ticket:** AH-14
- **Module:** worktree
- **Summary:** `harness worktree create` reports "Worktree created" and stops, whether or not the directory it just made carries the harness. Skill surfaces are installation artifacts rather than tracked files, so a project that keeps them out of Git gets a worktree with no `.claude/skills` and no `CLAUDE.md` symlink — and `references/worktree.md` sends the agent into exactly that directory as phase 2 of `harness-implement`. The cause sits one step earlier: `harness init` writes four surfaces and says nothing about Git, so whether worktrees work is decided by a `.gitignore` the user wrote by accident. This delta makes the state visible, gives it a repair path, and stops `init` leaving the decision to chance.
- **Target Module / Layer:** `core/scripts/stack-worktree.sh`, `install.sh`, `bin/harness`, `core/skills/worktree/SKILL.md`, `test/test_cli.sh`, `README.md`, `CHANGELOG.md`, `package.json`.

## 2. Requirements & Domain Floor Invariants
- [x] Requirement 1: `harness worktree create` evaluates the new worktree's surfaces and names the ones it does not carry, rather than reporting only that a directory exists.
- [x] Requirement 2: The report says whether the global surfaces still cover the worktree, so an absent local surface is not mistaken for an agent with no skills.
- [x] Requirement 3: `harness worktree seed <path>` installs the skill surfaces and the `AGENTS.md` symlinks into an existing worktree, and nothing else.
- [x] Requirement 4: Seeding refuses when the project tracks files under a surface directory. Those bundles carry the managed marker, so installing over them would delete and rewrite versioned files.
- [x] Requirement 5: `harness init` records the installed skill surfaces in the target's `.gitignore`, idempotently and inside the installation transaction, and names the files it expects to be committed instead. The `CLAUDE.md` and `GEMINI.md` symlinks are deliberately not ignored: committing them is what lets every worktree inherit `AGENTS.md`.
- [x] Invariant: Must not violate `rules/floor.md`. A command that cannot determine surface state says so rather than reporting a healthy worktree, and no command writes to a path it has not named.

## 3. Implementation Plan
1. [x] Add failing coverage to `test/test_cli.sh` for the report, the seed command, the tracked-surface refusal, and the `.gitignore` record.
2. [x] Add `--seed-target <path>` to `install.sh`, reusing `install_skill_surface` and writing the two symlinks, with no other target mutation.
3. [x] Report surface state after `git worktree add`, and add the `seed` action to `core/scripts/stack-worktree.sh`.
4. [x] Record the surfaces in the target's `.gitignore` from `install_target_repo`.
5. [x] Run `harness qa all` and the full suite.

## 4. Verification & QA
- **Automated Test Command:** `env -u STACK_PROFILE npm test`
- **Expected Outcome:** Green suite with zero regressions, including the new assertions in group 35, and a worktree created by the harness that either carries a surface or says which one it lacks.
