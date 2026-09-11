# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.10.0] - 2026-09-11

Four claims the project made about itself and did not back.

### Added

- `harness version` reports the installed version, the checkout it is running from, and
  that checkout's revision. The whole drift model turns on which version is installed —
  every surface manifest records one and `harness sync` compares against it — and there was
  no way to ask. The checkout is named because a CLI symlink can point anywhere, and the
  revision because a released version and a working checkout on the same version number are
  not the same thing.
- `harness upgrade` fast-forwards the checkout and re-synchronizes every managed surface.
  It refuses a checkout that is not a Git clone, one with a detached `HEAD`, one tracking no
  upstream, and one with uncommitted changes to tracked files. `--check` is a report rather
  than a gate: it names whatever it could not determine and still exits `0`.
- CI runs `harness scan --all` and `harness config validate` against this repository. The
  two commands the project asks every user to trust were the two it never exercised on
  itself.

### Changed

- `harness --help` lists `completion`, `version`, `upgrade`, and the `pr` alias of `ship`.
  A test now asserts that every command the dispatcher routes appears in the help, so the
  two cannot drift apart again — it found the undocumented `pr` alias on its first run.
- `specs/delta-AH-11-truthful-core-hardening.md` is archived. It was delivered in
  `7ea3705`, and an active spec for shipped work made `harness context` overstate what was
  in flight.

### Removed

- `forge` is no longer accepted by the dispatcher or offered by the shell completion. No
  such binary has ever existed.

## [2.9.0] - 2026-09-11

`harness ship` published whatever it was pointed at. On the trunk it pushed the trunk and
opened a pull request from `main` into `main`. With uncommitted work it pushed a branch
that was missing it and said nothing. It asked for no confirmation before a push, which
this project's own branch conventions forbid an agent from performing unasked.

> **Upgrade note — `harness ship` now asks before pushing.** Where there is no terminal to
> ask on it refuses rather than publishing, so a scripted or agent invocation must pass
> `--yes`. `--yes` is how a human confirms in advance; an agent must not pass it on its own
> initiative. A second change can turn a previously "successful" run into a failure: a run
> that pushed but opened no pull request now exits non-zero.

### Added

- `harness ship --dry-run` reports every decision — the branch, the target, the commit
  count — and mutates nothing, matching the flag `worktree remove` already offers.
- `harness ship --yes` confirms the push in advance.

### Changed

- Every guard runs before the QA suite, so a refusal costs no test run, and each refusal
  names what it found and leaves the repository untouched. `ship` refuses to publish the
  branch it is targeting, a detached `HEAD`, a target branch that exists neither locally
  nor on origin, a branch with no commits ahead of its target, and uncommitted changes to
  tracked files. Untracked files are reported rather than refused: they would not be pushed
  either way, and blocking on a scratch file would retire the command.
- Options are parsed rather than swallowed as a target branch. `harness ship --force`
  targeted a branch named `--force`.
- A run that pushed but opened no pull request exits non-zero and says which half happened,
  instead of reporting success. A missing `gh` or `glab`, a failing `gh pr create`, and a
  provider with no `ci.prCommand` all take that path.
- `gh pr create` is no longer retried without `--fill`. That retry prompts, and hung
  wherever there was no terminal.
- The help text stops advertising a "build commit" step `ship` has never performed.

## [2.8.0] - 2026-09-11

`harness init` copied a fixed template declaring every repository a Python "backend"
running `pytest`, with a GitHub issue prefix of `PROJ` and a trunk branch of `main`. In a
Node, Go, or Rust project the first command a new user ran — `harness qa all` — therefore
invoked `pytest`. The README already promised that init detects the language and test
runner, so the claim existed and the code did not honour it.

> **Upgrade note — this changes only what a *new* `harness init` writes.** An existing
> `stack.config.json` is left alone, as it always was. Re-run `harness init` in a
> repository whose configuration you never edited if you want the detected one.

### Changed

- `harness init` writes one profile per ecosystem it finds evidence of — Python, Node, Go,
  Rust — each with its own `detect` block, so a polyglot repository resolves the right
  profile per directory through the mechanism the configuration format already provides.
- Every command written is evidenced by a file in the target: a `test` script in
  `package.json`, `[tool.ruff]` in `pyproject.toml`, `manage.py` for Django (which is not
  pytest), `.golangci.yml` for golangci-lint. What is not evidenced is left unset, and init
  names each one so the reader knows what to fill in.
- Go and Rust record `"typeCheckCommand": false`. Their compilers type-check as part of
  building, so "this project has none" is a decision the target evidences rather than a gap.
- `ci.provider` and `issueTracker.provider` are read from the `origin` remote, or omitted.
  The `PROJ` issue prefix is gone: it was a fact about no repository in particular.
- `git.trunkBranch` is no longer written. Trunk detection already reads the repository at
  runtime, and a hardcoded `main` is wrong in any repository whose trunk is `master`.
- A target with no recognizable ecosystem gets a profile with no commands and a message
  naming the keys to set. An unconfigured gate that reports it could not run is correct.

### Fixed

- `schema.json` accepts `false` as well as a string for `qa.testRunner`, `qa.testCommand`,
  `qa.tddCommand`, `qa.lintCommand` and `qa.typeCheckCommand`. `stack-qa.sh` has documented
  and honoured `false` since 2.5.0, but `harness config validate` rejected it as
  "expected string, found boolean" — two parts of the harness disagreeing about what a
  configuration may legally say.
- The configuration validator understands a schema type expressed as a list of
  alternatives, and names them in the message it prints.

### Removed

- `core/templates/stack-config-template.json`, which nothing reads once init detects the
  project instead of asserting it.

## [2.7.1] - 2026-09-11

### Fixed

- Installation no longer aborts at random on macOS with
  `core/scripts/lib/surface.sh: line 77: printf: write error: Interrupted system call`.
  The three digest functions wrote to a pipe with a shell builtin while child processes
  were being reaped — `jq` in a process substitution, `basename` per reference, `cat` per
  file — and bash on macOS does not restart a write that the arriving `SIGCHLD`
  interrupts. A write large enough to fill the pipe buffer blocks, and a blocked write is
  what a signal can interrupt. The payload is now assembled in a regular file, whose
  writes are not interruptible, and the two short listings are accumulated in shell
  variables and handed to `sort` through a here-string. The race is removed rather than
  narrowed.
- The bytes fed to `git hash-object` are unchanged, verified digest by digest across every
  workflow and every installed bundle, so no existing surface manifest is invalidated and
  nothing is reported as drifted by this change alone. A test pins that contract: the
  source digest of a workflow equals the installed digest of the bundle published from it,
  and both equal a digest computed by an independent command.

  The failure was observed on `main` and on two branches, landing in a different matrix
  cell each time. A red run that carries no information about the change that produced it
  teaches everyone to ignore red runs, which is the one failure this project cannot afford.

## [2.7.0] - 2026-09-11

`harness worktree create` reported that a directory existed and stopped there, whether or
not the directory carried the harness. Skill surfaces are installation artifacts rather
than tracked files, so a project that keeps them out of Git got a worktree with no
`.claude/skills` and no `CLAUDE.md` — and `references/worktree.md` sends the agent into
exactly that directory as phase 2 of `harness-implement`.

### Added

- `harness worktree seed <path>` installs the four skill surfaces and the `AGENTS.md`
  symlinks into an existing worktree of the repository, and writes nothing else. It
  refuses a path this repository does not own, and refuses a project that tracks its
  surfaces in Git: those bundles carry the managed marker, so installing over them would
  delete and rewrite versioned files.
- `./setup --seed-target <path>` is the installer mode behind it, transactional and
  reversible through `./setup --rollback` like any other installation.

### Changed

- `harness worktree create` now names the surfaces the new worktree carries and the ones
  it does not, says whether the global surfaces still cover it, and prints the one command
  that gives it its own. A worktree with no surface is a fact the reader can act on; the
  previous "Worktree created" alone was not.
- `harness init` records the skill surfaces it installs in the target's `.gitignore`,
  idempotently and inside the installation transaction, and names the files it expects to
  be committed instead. Whether a project's worktrees inherit the harness used to be
  decided by a `.gitignore` its owner wrote by accident.
- The `CLAUDE.md` and `GEMINI.md` symlinks are deliberately **not** ignored. They cost
  nothing in Git, and committing them is what carries `AGENTS.md` into every worktree
  without seeding anything.

## [2.6.0] - 2026-09-11

Three places where the scanner reported a passing scan having verified nothing. All three
are the AH-9 shape the rest of the harness already closed: a check that could not run must
never read as a check that passed. One of them can turn a previously green run red, and it
is a correction rather than a regression — read it first.

> **Upgrade note — the scan gate inside `harness qa all` now reads the branch, not the
> working tree.** It ran in `--diff` mode, which compares the working tree against `HEAD`.
> On a finished branch that set is empty, so a secret committed three commits earlier was
> reported as "No files to scan", the aggregate suite printed "All required QA gates
> passed", and `harness ship` pushed it. `qa all` now scans in `--branch` mode: everything
> the branch changes since its merge base with the trunk. A branch that was already
> carrying a finding will fail on the next run — that finding was always there.

### Added

- `harness scan --branch` scans every change the current branch makes since its merge base
  with the trunk: committed work, tracked files edited but not committed, and new files
  already staged. Untracked files stay out, because the branch does not carry them.
- `harness scan --base <ref>` names that base explicitly, for a shallow CI clone where the
  trunk ref is not present locally (`--base origin/main`).
- Exit status `2` — "the scan could not run" — distinct from `1`, "the scan ran and found
  something". It is the status `stack-qa.sh` already aggregates as `GATE_UNRUNNABLE`, so an
  unresolvable range, an unreadable rule file, and an uncompilable rule are all reported by
  `harness qa all` as a gate that could not run.

### Changed

- `harness qa all` runs its scan gate as `--branch` rather than `--diff`.
- "No files to scan" now names the selection that was empty (`the branch selection is
  empty`), so a truthful zero can be told apart from the wrong question.

### Fixed

- A `--rules <file>` path, or a configured `profiles.<p>.rules.scanner`, that does not
  resolve now aborts the scan naming the file it could not read. It was silently replaced
  by the built-in template, so a project whose `rules/landmines.json` had been renamed was
  scanned by rules nobody there wrote and told it passed. A missing template made the scan
  exit `0` outright.
- `harness scan`, `harness context`, and `harness doctor` refuse an option they do not
  define instead of discarding it. `harness scan --al` scanned the staged set — empty on a
  clean tree — and exited `0`; `harness context --jsonn` printed prose to a caller parsing
  JSON; `harness doctor --fixx` diagnosed and repaired nothing while reading as though
  `--fix` had been honoured.
- `--base` without `--branch` and `--force` without `--install-hook` are refused rather
  than accepted and ignored.

## [2.5.0] - 2026-09-11

An audit of the installed harness found twenty-six defects, and almost every one was the
same shape: the harness stated something it had not verified. This release closes all of
them. Two can turn a previously green run red, and both are corrections rather than
regressions — read them first.

> **Upgrade note 1 — the lint and type gates now fail closed.** Their unconfigured defaults
> ended in `|| echo 'No linter configured'`, so a repository with neither `ruff` nor
> `npm run lint` passed both gates and `harness qa all` printed "All required QA gates
> passed" having checked nothing. A gate with nothing configured for it now reports that it
> **could not run** and exits non-zero. Set `qa.lintCommand` and `qa.typeCheckCommand`, or
> set either to `false` to record that the project has none — that gate then reports as
> *declared absent* and does not fail the suite.

> **Upgrade note 2 — `config.example.json` is no longer a configuration fallback.** A
> repository with no configuration of its own resolved to the example shipped in this
> repository, silently adopting its fictional `backend` profile, its `pytest`/`ruff`/`mypy`
> commands, and its `targetRepoPath` of `~/projects/backend-api`. An unconfigured repository
> now resolves to the built-in defaults under the profile name `default`. If your project
> was relying on the example, copy it to `harness.config.json` and edit it.

### Added
- `harness config validate` reports the configuration file that was resolved, the active profile and how it was chosen, and every structural problem it can determine by walking `schema.json`: invalid JSON, a key whose type the schema contradicts, a key the schema does not describe, a `defaultProfile` naming no profile, and a `targetRepoPath` that does not exist. It is a structural walk rather than a JSON Schema engine, and it prints which checks it did not perform.
- `harness doctor` performs the three checks `core/skills/doctor/SKILL.md` has always claimed for it and never did: whether the `~/.local/bin` CLI symlinks resolve to this checkout and their directory is on `PATH`; whether the repository's `pre-commit` hook is agent-harness's own, a foreign hook, or absent; and whether the resolved configuration validates. A configuration that does not validate is an error, not a warning.
- `harness doctor --check-auth` reports whether the configured issue and CI provider CLIs are authenticated. It was advertised, parsed, assigned to a variable no check read, and marked in the source with its own `# defer:` marker.
- `harness receipt list`, `harness receipt show <run_id>`, and `harness receipt prune [--keep <count>]`. The receipt command has been write-only since AH-3: it produced an observability record the user it was produced for could not read back, and nothing ever removed one. An open receipt is never pruned — an abandoned run is a finding, not litter.
- Scanner rules may match a repository-relative **path** through `pathPattern` instead of content through `pattern`, exactly one of the two. The scanner previously had no way to express a forbidden *filename*, so it could not block `.env`, `*.pem`, `*.key`, or a committed agent directory — the first thing a pre-commit gate is installed to stop. `SEC-003` ships in `rules/landmines.json`, in the template, and in every recipe.
- `excludePaths` glob lists scope a rule without switching it off, and `harness-ignore: <RULE-ID>` on the matching line or the line above exempts one finding for one rule. Without an escape hatch the only way past a false positive was `--no-verify`, which retires the whole gate rather than one line.
- Every recipe now ships the `rules/landmines.json` its `stack.config.json` has always declared. All three declared `./rules/landmines.json` and none provided one, so a TypeScript or Go project initialized from a recipe inherited the Python template's `.objects.all()` and `cursor.execute(f"` rules and was scanned for defects it could not have.
- `harness completion install` writes a Bash completion alongside the Zsh one. The README has advertised "Shell Autocompletion (Zsh & Bash)" since the command existed while only the Zsh file was ever written, and the Zsh command list had drifted behind the dispatcher.
- `harness worktree remove --dry-run`, and `--force` as the explicit way to discard uncommitted work.
- `./setup --yes` confirms a guided installation without a prompt, for scripted and agent invocations.
- `core/scripts/lib/specs.sh` and `core/scripts/lib/debt.sh`, so that "which delta specs are active" and "where are the debt markers" each have one implementation shared by the command that reports them and the command a human would run to check.

### Fixed
- `harness context` reported twelve active delta specs in a repository whose active count was zero: it recursed into `specs/archive/` while `harness spec status` correctly did not. Both now read the same helper.
- `harness context` reported `0` technical debt markers because `ripgrep` was absent, not because the markers were. It called `rg` with no fallback while `harness debt` fell back to `grep` and found ten in the same tree. Both now scan tracked files through `git grep`, which also removes the divergence between `ripgrep` honouring `.gitignore` and `grep -r` not. A scan that cannot complete reports `null`, never zero — and an unreadable file is detected on stderr, because `git grep` reports one as a diagnostic and still exits with its code for "no match".
- `harness context --json` is emitted by `jq`. Assembled by a heredoc, a quote or backslash anywhere in a repository path, branch, or profile name produced a document no consumer could parse.
- `harness worktree remove <key>` interpolated the key into `grep` as an unanchored pattern and passed `--force` to every match. In the reproduction `harness worktree remove wt-AH` removed both `wt-AH-1` and `wt-AH-2` and destroyed an unsaved file, with no prompt and nothing to recover it from. It now matches an exact path, directory name, or branch issue segment, names every match before removing anything, refuses an ambiguous key, and refuses to discard uncommitted work without `--force`.
- `harness ship` ran `git push … 2>/dev/null || log_warn "Push skipped or branch already up to date."`, turning a rejected non-fast-forward, a missing remote, and an expired credential into a warning before opening a pull request for a branch that was never pushed. A failed push now aborts before the pull request step and reports git's own stderr.
- `harness scan` exited `0` and printed "passed with 0 errors" when `jq` was unusable, skipping the rule loop entirely. Recorded as a deferred open question in AH-9; it now fails closed.
- `harness commit check` could only ever warn, so a subcommand named `check` could not be used as a gate. It now exits non-zero on a message that does not conform.
- `harness commit build` refuses to commit when nothing is staged, instead of printing a success-shaped "Generated commit message" line and then surfacing git's own error. The unanchored issue-key pattern this delta also carried a fix for was landed first as AH-12 in 2.4.2; that implementation is the one kept, and this delta's test for a lowercase slug carrying a digit (`feat/add-2fa-support`) is kept alongside AH-12's group.
- `harness sync --check` and `harness doctor` called a surface `current` while it published skills no manifest recorded. In the audited installation fourteen obsolete skills — including `ship`, which the catalog marks removed — were published into `~/.claude/skills` from a second checkout, and were unreachable to repair as well: `remove_managed_skill` matched only symlinks under the current `HARNESS_ROOT`, so no later run from any other checkout could clean them up. Managed entries are now recognized by shape, reported as drift when unrecorded, and removed by name by `harness sync`. Skills agent-harness does not manage are still left exactly where they are.
- `--base <branch>` is parsed by `harness branch create` and `harness worktree create`. Both advertised it and read the base from the fourth positional argument, so `--base` reached `git checkout -b` as a revision and printed git's usage text instead of creating anything. The fourth positional form still works.
- `--module <name>` is parsed by `harness spec create`. It records the module inside the spec, which `harness spec archive` reads back, rather than moving the file out of `specs/` where "active" is defined.
- `harness spec create` rejects an issue key or slug containing a path separator or a `..` segment. `harness spec create AH-1 a/b` reached `sed` and failed with a raw redirection error naming a path outside `specs/`.
- `harness debt --all` is parsed and means "include untracked files"; it was advertised and dropped. `harness debt --json` emits a single array of `{file, line, text}` — it previously emitted either a human log line or `ripgrep`'s JSON-Lines stream, neither of which any consumer could parse, and both `/harness-implement` and `/harness-fix` instruct agents to call it. The marker pattern now also recognizes `//` comments, so the TypeScript and Go recipes can carry markers at all.
- `harness spec status --json` emits the active delta specs as a JSON array; the flag was advertised in the dispatcher help and dropped with every other argument, so the JSON form printed the human listing. `resolve_spec_path` now shares the same definition of "active" as `spec status` and `context`.
- The dispatcher help lists `orchestrate` among the workflows `harness receipt start` accepts. It has accepted it since AH-7 and the help named only three.
- `harness init --recipe <unknown>` exits non-zero and names the available recipes. It tested `[ -d recipes/<name> ]`, installed no recipe, and reported success.
- `harness --profile` with no value exits non-zero naming the missing argument. It ran `shift 2` with one argument remaining, which under `set -e` exited `0` having done nothing.
- `./setup` is advertised as a guided interactive installer and asked nothing. Run from `$HOME` it installed `AGENTS.md`, a `CLAUDE.md` and `GEMINI.md` symlink, `stack.config.json`, `rules/`, and four skill surfaces into the home directory. It now names both destinations and waits; with no terminal it refuses and names `--yes`, `--global`, and `--target` rather than assuming consent. It also refuses a directory that is not a Git repository, which every workflow the installed surface describes requires. An explicit `--target` is a deliberate choice and is reported rather than refused.
- `./setup --yes` (or any run naming only modifiers) selected no action at all and still printed "Setup complete!". Guided is now the default scope, as the usage text always said.
- `get_profile_value` returned the caller's default for any value configured as `false`: jq's `//` treats `false` as empty, so nothing could be switched off by configuration. It now selects the first key that is *present*.
- `lib/config.sh` and `stack-scan.sh` passed configuration values to `eval`, so a configuration file containing a command substitution executed it. A leading `~` is expanded by parameter substitution instead.
- `test/test_cli.sh` no longer rewrites the developer's own global skill surfaces. Its doctor group ran `harness doctor --fix` without isolating `HOME`, and `doctor --fix` repairs both the scopes doctor reports on -- one of which is derived from `$HOME` -- so running the suite synchronized the real `~/.claude`, `~/.gemini`, `~/.codex`, and `~/.agents` surfaces. `HOME` is now isolated for that group, and the two-scope repair is asserted inside the isolated home rather than assumed.
- Committed transaction journals are pruned to the ten most recent. Each holds a full backup of every file its installation replaced and nothing ever removed one; the journal `--rollback` can still undo is never pruned.

### Removed
- `core/scripts/lib/ai-client.sh`, and the `localAI` block from `schema.json` and `config.example.json`. The library was sourced by nothing, so it had never run, and its configuration lived at the schema's top level while `get_profile_value` only reads `.profiles[…]` and `.project` — it could not have been enabled even by a user who tried. `harness doctor` no longer probes for `ollama` and no longer treats `curl` as required, since no reachable code path used it.

## [2.4.2] - 2026-09-11

### Fixed
- `harness commit build` read a Conventional Commit scope out of any branch carrying a version number: `chore/release-2.4.1` recorded `chore(release-2): …` and `fix/bump-node-22-1` recorded `fix(node-22): …`. The issue-key pattern accepted a lowercase word as a project prefix and left its digits unbounded on the right, so they stopped at the first dot. A key is now an uppercase prefix, a hyphen, and digits that are not followed by a dot: `AH-11` and `COMPAT-1` still scope their commits, and a version-like branch is left unscoped rather than scoped to a fragment of the version.

## [2.4.1] - 2026-09-11

### Added
- Complementary Tooling section in `docs/PROVENANCE.md`, recording `mksglu/context-mode` as a tool that runs alongside `agent-harness` without being invoked by it, and a fifth relationship term for that case. Its Elastic-2.0 license is noted as the standing constraint on borrowing source into this MIT-licensed repository.

## [2.4.0] - 2026-09-11

### Added
- Every installed skill surface now records what it is. `.agent-harness-surface.json` carries the schema, namespace, harness version, installed mode, runtime, and one entry per skill — a `bundle` with a digest of its source content, or a `symlink` without one, because a symlinked expert primitive follows the source and cannot go stale. The digest prefixes every file with its relative path, so a reference republished under a new name signs differently from the original.
- `harness sync --check` reports each identified surface as current, drifted, or unmanaged, with a reason per drifted surface, and exits non-zero if any is stale. It mutates nothing, so it is usable from CI and from a read-only workflow.
- `harness doctor` reports the same surface states. Drift is a warning and doctor still exits `0`, because a stale surface works — it is out of date, not broken. `harness doctor --fix` synchronizes what it found. A check that cannot run reports as unavailable, never as clean.
- `core/scripts/lib/surface.sh`, shared by the installer, sync, and doctor, so that "what should this surface contain?" has one implementation rather than two that can disagree.

### Fixed
- `harness sync` reached only the global surfaces, so a repository initialized with `harness init` kept the skills it was installed with forever. It now synchronizes the current repository's surfaces as well, with `--target <path>` and `--global` to narrow the scope.
- `harness sync` silently downgraded an expert installation to curated. It removed every managed primitive and, never having been passed `--expert`, reinstalled none: a 19-skill expert surface became a 4-skill curated one with nothing said. Synchronization now preserves the mode recorded in the manifest.
- The installer reported success after refusing to write a published skill name occupied by a path it does not manage. It now fails and rolls the transaction back, so the alternative to a complete surface is the previous one rather than a partial one.

### Changed
- Compatibility evidence moves to `schemaVersion: 3` and gains a `surfaceManifest` boolean; the matrix asserts the manifest for the scope and mode of each cell.
- The README version badge now tracks `package.json`.

> **Upgrade note.** Every surface installed before this release has no manifest and is reported `drifted` with the reason `no recorded version`. That is accurate rather than alarming: those surfaces really are of unknown provenance, and several were genuinely stale — this repository's own four and all five global ones were still carrying the 2.1.0 `/harness-implement` without the AH-8 stagnation breaker, and `harness-orchestrate` had never been installed anywhere despite shipping in 2.1.0. One `harness sync` clears it.

## [2.3.0] - 2026-09-10

### Fixed
- `./setup --verify` now exits non-zero when a shell script fails `bash -n` or a `SKILL.md` is missing its frontmatter. Both checks previously printed their failures and still ended with `Verification completed successfully!` and exit `0`: `find -exec bash -n {} \;` discards every status, and the frontmatter loop ran inside a `find | while` pipeline subshell. CI ran this as its verification step, and `harness.config.json` runs it as the repository's lint command, so both gates were decorative. One invocation now reports every problem and exits `1` if any were found.
- `harness scan --staged` reads staged content from the Git index instead of the working tree. It resolved staged *paths* correctly and then grepped whatever was on disk, so a violation that was staged and then reverted committed clean, and a violation that existed only on disk blocked a commit that did not contain it. The installed pre-commit hook runs this mode, so the gate was answering a question nobody asked. Staged blobs are materialized once per file, before the rule loop, and removed when the scanner exits. A path staged as an addition and then deleted from disk is no longer skipped. `--diff` and `--all` still read the working tree, which is what they describe.
- `harness scan --install-hook` no longer destroys a pre-existing `pre-commit` hook. It refuses, names the hook, and prints the line to add manually. The generated hook carries a marker, so re-running over agent-harness's own hook stays idempotent. `--force` replaces a foreign hook after copying it to `pre-commit.harness-backup`, and refuses if that backup already exists. The hooks directory is now resolved through `git rev-parse --git-path hooks`, so installation works from a linked worktree.
- A scanner rule whose pattern `grep -E` cannot use now aborts the scan with a non-zero status naming the rule ID. Two checks run: any pattern containing `(?` is refused because it opens a PCRE group construct that ERE does not define, and every remaining pattern is compiled once against empty input. Both are needed, because BSD `grep` rejects a lookahead outright while GNU `grep` compiles it and then matches something nobody wrote — a compile check alone would refuse the same rule on macOS and accept it on Linux. The shipped `PERF-001` was exactly that case: its `(?!\.iterator|\.values|\[)` is a PCRE negative lookahead, and the rule had never produced a finding in this repository or in any project initialized from the template. It is rewritten as an ERE that matches `.objects.all()` only when the call ends the expression, in both `rules/landmines.json` and `core/templates/landmines-template.json`.

### Changed
- The README version badge now tracks `package.json`; it had been pinned at `2.0.0` since the `2.1.0` release.

> **Upgrade note.** The scanner change alters which inputs the gate rejects. A repository whose pre-commit hook was passing because the scan read the working tree may now see it fail, and a project whose ruleset contains a pattern `grep -E` cannot compile will see `harness scan` refuse to run until that pattern is fixed. Both are corrected defects rather than new restrictions, but neither is a silent upgrade.

## [2.2.0] - 2026-09-09

### Added
- Deterministic failure signatures and a stagnation breaker for the bounded review loop. `harness ledger failure <run_id> [label]` reads a verification capture on stdin, records only its 12-character signature, and answers `continue` on exit `0` or `stagnant` on exit `3`; `harness ledger signature` exposes the same normalization on its own. Normalization scrubs ISO-8601 timestamps, absolute directory prefixes, line and column suffixes, and runs of six or more digits, so two failures differing only in that noise sign identically — including two captures of one failure taken from different checkouts.
- `failure` as a ledger kind, and `profiles.<profile>.loop.stagnationThreshold` (default `2`, minimum `2`) in `schema.json`.

### Changed
- Phase 7 of `/harness-implement` now has a second exit. Previously the three-round cap was the only way out, so a loop that failed the same way three times spent its whole budget re-deriving one failure before it could adjudicate. It now signs every failed round and adjudicates as soon as consecutive rounds sign alike. The cap itself is unchanged, and stagnation can only end the loop earlier than the cap, never later.

## [2.1.0] - 2026-09-09

### Added
- `/harness-orchestrate`, a fourth public workflow that executes an approved delta spec's implementation plan one item at a time, dispatching an implementer subagent and then a separate reviewer subagent that sees the diff but never the implementer's reasoning. It requires subagent dispatch and has no degraded single-context mode; where dispatch is unavailable, `/harness-implement` is the equivalent.
- Per-runtime skill gating. `core/skills/catalog.json` carries a `runtimes` map, and `install.sh` installs a gated public workflow only into the runtimes it names. A workflow absent from the map still reaches every runtime. Removal stays unconditional, so a newly gated workflow leaves the disallowed runtimes without a migration step.
- Per-role model selection under `profiles.<profile>.orchestrate.models`, surfaced by `harness context --json` as `orchestrateModels` and defaulting to `sonnet` for the implementer and `opus` for the reviewer.
- `orchestrate` is a valid execution receipt workflow, with the phase tokens `admit`, `dispatch`, `review`, `resolve`, and `close`.

### Changed
- The compatibility matrix verifies the surface each runtime is declared to receive rather than an identical surface everywhere, and asserts that a gated workflow is absent from every other runtime. Its evidence artifact moves to `schemaVersion: 2` and gains a `runtimeGating` boolean.

## [2.0.0] - 2026-09-09

### Added
- Durable progress ledger (`harness ledger start|append|show|rulings`), stored beside execution receipts under the repository's Git common directory and keyed by the same run ID. It is the run's memory across a compacted context, and it holds the free-form narrative that the closed receipt schema cannot carry.
- Bounded review loop in `/harness-implement`: Minor findings never enter the loop, Critical and Important ones do for at most three rounds, and at the cap every open finding is adjudicated as parked-with-ruling or load-bearing. A load-bearing finding ends the run `blocked` instead of reporting success over a known defect.
- Finding severity classification (Critical, Important, Minor) in `/harness-review`, which the bounded loop consumes.
- Upstream Drift Audit in `docs/PROVENANCE.md`, recording the verified upstream head, drift, and method delta for every acknowledged influence, plus the re-verification command.
- Reversible installer transactions (`core/scripts/lib/transaction.sh`). Every mutation is journaled before it is applied, a mid-install failure restores the previous filesystem state automatically, and `./setup --rollback` undoes the last committed installation.
- `test/test_transaction_lib.sh` and `test/test_install_transaction.sh`, covering the journal primitives and end-to-end installation rollback.
- ShellCheck linting (`npm run lint`) over `bin`, `core/scripts`, `install.sh`, and `setup`, wired into CI on both runners alongside the two new suites.

### Changed
- **BREAKING.** Every published skill is namespaced `harness-*` across Gemini, Claude, Codex, and `.agents`. A `1.0.0` invocation of `/tdd`, `/review`, `/spec`, or any other primitive must become `/harness-tdd`, `/harness-review`, `/harness-spec`. Legacy managed aliases are cleaned up on install.
- `install.sh` now runs under `set -Eeo pipefail` and performs every filesystem mutation through the transaction library. A failure while linking the CLI aborts and rolls back the installation instead of warning and continuing.

### Removed
- **BREAKING.** `/ship` is no longer published as a skill. The CLI equivalent `harness ship` is unchanged.
- **BREAKING.** A default installation exposes only `/harness-implement`, `/harness-fix`, and `/harness-investigate` instead of the fourteen standard skills announced in `1.0.0`. The primitives are bundled privately inside those workflows and can still be exposed as standalone skills with `--expert`.

### Fixed
- `harness spec status` listed archived specs as active. Its `find` recursed into `specs/archive/` and matched directories, unlike `resolve_spec_path`, which was already scoped with `-maxdepth 1 -type f`. Archiving a spec now removes it from the active listing.
- `harness doctor --fix` aborted with a Bash `local` error instead of restoring a missing `AGENTS.md`.

## [1.0.0] - 2026-08-26

### Added
- Multi-Call CLI Dispatcher (`bin/harness`) with dynamic alias routing (`agh`, `agent-harness`).
- Universal Multi-Harness bridge (`.gemini`, `.claude`, `.codex`, `.cursor`, `.agents`).
- 14 Standard Agent Skills: `/task`, `/bug`, `/tdd`, `/review`, `/spec`, `/doctor`, `/qa`, `/scan`, `/worktree`, `/conflicts`, `/questionnaire`, `/debt`, `/commit`, `/ship`.
- Rule-driven JSON Landmine & Security scanner (`harness scan`).
- Sub-second workspace context extractor (`harness context`).
- Living Delta Specs (Spec-Driven Development / OpenSpec).
- Starter recipes for Python FastAPI, TypeScript Fullstack, and Go Microservices.
- One-line universal installer & verification test suite (`./setup --verify`).
