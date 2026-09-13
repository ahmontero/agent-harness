# 🚀 agent-harness

<p align="center">
  <a href="package.json"><img src="https://img.shields.io/badge/version-2.14.0-blue.svg" alt="Version" /></a>
  <a href=".github/workflows/ci.yml"><img src="https://github.com/ahmontero/agent-harness/actions/workflows/ci.yml/badge.svg" alt="CI Status" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-lightgrey.svg" alt="License: MIT" /></a>
  <a href="README.md"><img src="https://img.shields.io/badge/Harnesses-Antigravity%20|%20Claude%20Code%20|%20Codex%20|%20Cursor%20|%20.agents-purple.svg" alt="Multi-Harness" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs Welcome" /></a>
  <a href="https://www.conventionalcommits.org/"><img src="https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg" alt="Conventional Commits" /></a>
</p>

```text
   ___                    __     __ __                               
  / _ | ___ _ ___  ___   / /_   / // / ___ _ ____ ___  ___  ___ ___
 / __ |/ _ `/ -_)/ _ \ / __/  / _  / / _ `/ __// _ \/ -_)(_-<(_-<
/_/ |_|\_, / \__/ /_//_/ \__/  /_//_/  \_,_//_/  /_//_/\__//___//___/
      /___/                                                          
```

> **The Universal Engineering Harness & Quality Floor for AI Coding Agents.**  
> Stop AI agents from breaking production. Enforce strict Red-Green TDD, 6-phase deterministic debugging, living delta specs, and pre-commit landmine scanners across **Google Antigravity**, **Claude Code**, **OpenAI Codex**, **Cursor**, and standard `.agents`.

<p align="center">
  <img src=".github/assets/demo.gif" alt="agent-harness terminal demo" width="800" />
</p>

---

## 📑 Table of Contents

- [⚖️ Why agent-harness? (The Agent Quality Gap)](#️-why-agent-harness-the-agent-quality-gap)
- [🌐 Universal Multi-Harness Compatibility](#-universal-multi-harness-compatibility)
- [⚡ 10-Second Quickstart](#-10-second-quickstart)
- [🚦 Engineering Workflows](#-engineering-workflows)
- [🧠 Internal Engineering Protocols](#-internal-engineering-protocols)
- [🛡️ Injecting Domain Rules & Landmines](#️-injecting-domain-rules--landmines)
- [💻 Multi-Call CLI Dispatcher (`harness`)](#-multi-call-cli-dispatcher-harness)
- [🍳 Ready-to-Use Recipes](#-ready-to-use-recipes)
- [🏛️ Architecture & System Design](#️-architecture--system-design)
- [🙏 Acknowledgements & Provenance](#-acknowledgements--provenance)
- [🤝 Contributing & Community](#-contributing--community)

---

## ⚖️ Why agent-harness? (The Agent Quality Gap)

Autonomous AI coding agents are exceptionally capable, but without a strict engineering harness, they inevitably degrade codebases:

```
❌ Without agent-harness:
   1. The agent immediately edits source code without creating reproduction tests (Violating TDD).
   2. Modifies code directly in your active branch, leaving untracked experimental debris.
   3. Rationalizes cutting corners ("this fix is too simple for tests/specs", over-mocking).
   4. Introduces unindexed database queries or raw SQL, bypassing historical architectural invariants.
   5. Blindly patches symptoms upon error without isolating the deterministic root cause.
   6. Dumps walls of conversational text and wanders off on unrelated tangents.

✅ With agent-harness:
   1. Strictly enforced Red-Green-Refactor loop (`/harness-tdd`) with Anti-Rationalization Gates.
   2. Automatic branch/worktree isolation (`/harness-worktree`) keeps your workspace clean.
   3. Anti-Rationalization Matrices cut off LLM excuses across all critical engineering skills.
   4. Static JSON AST/regex scanner (`/harness-scan`) prevents known landmines before commit.
   5. Matt Pocock-inspired 6-Phase Deterministic Debugging (`/harness-bug`) with tagged probe instrumentation.
   6. Action-First & State-Anchored communication with automatic debt harvesting (`/harness-debt`).
```

---

## 🌐 Universal Multi-Harness Compatibility

`agent-harness` unifies your engineering standards across every major agent runtime:

| AI Runtime / IDE | Auto-Linked Skills | Quality Floor & Rules | Pre-Commit Scanner | Worktree Isolation | Sub-Second Context (<1s) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Google Antigravity** | ✅ (`.gemini/skills`) | ✅ (`rules/` via `AGENTS.md`) | ✅ | ✅ | ✅ (`harness context`) |
| **Claude Code** | ✅ (`.claude/skills`) | ✅ (`rules/` via `AGENTS.md`) | ✅ | ✅ | ✅ (`harness context`) |
| **Cursor Agent** | ✅ (`.agents/skills`) | ✅ (`rules/` via `AGENTS.md`) | ✅ | ✅ | ✅ (`harness context`) |
| **OpenAI Codex** | ✅ (`.codex/skills`) | ✅ (`rules/` via `AGENTS.md`) | ✅ | ✅ | ✅ (`harness context`) |
| **Generic (.agents)** | ✅ (`.agents/skills`) | ✅ (`rules/` via `AGENTS.md`) | ✅ | ✅ | ✅ (`harness context`) |

The installation contract is exercised as an eight-cell Ubuntu/macOS matrix covering target and global installation in both default and expert modes. See [Verified Compatibility](docs/COMPATIBILITY.md) for the exact assertions, evidence artifacts, and reproducible commands.

---

## ⚡ 10-Second Quickstart

### 1. One-Line Global Installation

```bash
# ⚡ Install globally without a language runtime or package bundle
curl -fsSL https://raw.githubusercontent.com/ahmontero/agent-harness/main/install.sh | bash

# Or via npm
npm install -g @ahmontero/agent-harness
```

*Or via local clone:*
```bash
git clone https://github.com/ahmontero/agent-harness.git
cd agent-harness
./setup --global

# Optional: expose advanced primitive skills as standalone commands
./setup --global --expert
```

Every installation is transactional. Each mutation is journaled before it is applied, a failure part-way through restores the previous filesystem state automatically, and a completed installation can be undone:

```bash
./setup --rollback
```

Journals live under `$XDG_STATE_HOME/agent-harness` (or `~/.local/state/agent-harness`) and are created with `umask 077`. Set `HARNESS_STATE_DIR` to relocate them.

### 2. Initialize in Any Existing Project

```bash
cd ~/projects/my-awesome-app

# Run with harness CLI (or npx @ahmontero/agent-harness)
harness init
```

`harness` will automatically:
- Detect the ecosystems the repository shows evidence of — Python, Node, Go, Rust — and write one profile for each, with its own `detect` block so a polyglot repository resolves the right one per directory.
- Write only commands the target evidences: a `test` script in `package.json`, `[tool.ruff]` in `pyproject.toml`, `manage.py` for Django, `.golangci.yml` for golangci-lint. What it cannot evidence it leaves unset and names, because a gate that reports it could not run is correct and a gate that runs the wrong tool is not.
- Generate `stack.config.json` and a starter `rules/` directory. It states no issue-key prefix and no trunk branch: neither can be read from the repository, and trunk detection already happens at runtime.
- Install the curated workflow bundles through `.gemini`, `.claude`, `.codex`, and `.agents`. The quality floor and the landmines are not copied per runtime: they live once in `rules/`, named by `AGENTS.md` and by `stack.config.json`, and every runtime reads them from there.

---

## 🚦 Engineering Workflows

Most work starts with one of three intent-level workflows. Their private protocol bundles preserve the underlying engineering gates without exposing every primitive as a user command:

```text
/harness-implement <requirement>     Build or change behavior through spec-aware TDD, QA, and review.
/harness-fix <defect>                Reproduce, prove root cause, add a regression test, and apply a surgical fix.
/harness-investigate <question>      Gather evidence, compare options, recommend, and stop without editing.
```

The `harness-` namespace is used consistently in Gemini, Claude, Codex, and `.agents`, preventing collisions with generic or third-party skill names. CLI commands remain unchanged (`harness qa`, `harness scan`, and so on).

`/harness-implement` and `/harness-fix` produce verified working-tree changes but never publish them without an explicit request. `/harness-investigate` is read-only and cannot silently transition into implementation.

### A fourth workflow, on Claude Code only

```text
/harness-orchestrate <delta-spec>    Execute an approved plan item by item, dispatching one implementer
                                     and one reviewer subagent per item, with a model chosen per role.
```

`/harness-orchestrate` requires subagent dispatch, which is not a capability every runtime exposes, so the installer places it in Claude Code and nowhere else. It has no degraded single-context mode on purpose: where dispatch is unavailable, `/harness-implement` applies the same engineering gates inside one context, and the workflow tells you so instead of pretending to orchestrate.

| Workflow | Antigravity | Claude Code | Codex | Cursor | `.agents` |
| :--- | :---: | :---: | :---: | :---: | :---: |
| `/harness-implement` | yes | yes | yes | yes | yes |
| `/harness-fix` | yes | yes | yes | yes | yes |
| `/harness-investigate` | yes | yes | yes | yes | yes |
| `/harness-orchestrate` | no | yes | no | no | no |

Its value is role separation rather than speed: each plan item gets an implementer with a fresh context, and a reviewer that receives the diff and never the implementer's reasoning. Dispatch is strictly serial, because two subagents editing one working tree is a race, not a speedup. Models per role are configured under `profiles.<profile>.orchestrate.models` and default to `sonnet` for the implementer and `opus` for the reviewer.

### Local execution receipts

The workflows record a small JSONL lifecycle receipt inside the repository's private Git metadata. Nothing is added to the working tree or sent remotely, and the schema does not accept prompts, code, file paths, secrets, or free-form evidence.

```bash
run_id="$(harness receipt start implement --issue PROJ-123)"
harness receipt phase "${run_id}" tdd passed
harness receipt phase "${run_id}" qa passed
harness receipt finish "${run_id}" completed
```

Receipts live under `.git/agent-harness/runs/`, are shared across the repository's worktrees, and provide the input contract for future local statistics.

### Progress ledger and the bounded review loop

A receipt is a closed schema, so anything that needs words goes to the run's ledger instead. Every workflow opens one at start, keyed by the same run ID, and uses it to survive a compacted context. `/harness-implement`, `/harness-fix` and `/harness-orchestrate` also use it to record every decision they took on your behalf; `/harness-investigate` keeps only the memory, because it is read-only and has no correction to re-review.

```bash
harness ledger start "${run_id}"
harness ledger append "${run_id}" phase "round 2/3 (3 addressed, 1 open)"
harness ledger append "${run_id}" parked "reviewer disputed the awk filter — Ruling: the code stands"
harness ledger rulings "${run_id}"
```

The bounded review loop itself lives in one place — `references/loop.md`, bundled into the three workflows that run it — because two hand-maintained copies of one protocol drift, and these two had: the dispatched copy had quietly lost its stagnation breaker. The ledger is what makes that gate terminate. Minor findings never enter the fix loop; Critical and Important ones do, for at most three rounds. At the cap the agent must adjudicate every finding still open, either parking it with a recorded ruling or declaring it load-bearing, in which case the run ends `blocked` rather than reporting success over a known defect. Discarding a finding without a ledger line is forbidden, and `harness ledger rulings` is reproduced in full in the agent's final message.

The cap is not the only exit. A loop whose verification keeps failing the same way stops early:

```bash
harness qa test 2>&1 | harness ledger failure "${run_id}" "round 2/3"
# -> continue   (exit 0)
# -> stagnant   (exit 3)
```

`harness ledger failure` reduces the verifier output to a 12-character signature, scrubbing the detail that changes between runs — timestamps, absolute paths, line and column numbers, and long numeric IDs — so that two failures which differ only in noise sign identically. When the run's last two signatures match, the loop is not converging and the agent goes straight to adjudication instead of spending its third round re-deriving one failure. `profiles.<profile>.loop.stagnationThreshold` raises that count; it cannot be lowered below two. `harness ledger signature` exposes the same normalization on its own, reading a capture on stdin.

Only the signature is recorded. The verifier output never reaches the ledger, so the run keeps the evidence-free property that lets receipts and ledgers stay local and private.

Ledgers live under `.git/agent-harness/ledgers/`, are readable only by their owner, and never leave the repository.

---

## 🧠 Internal Engineering Protocols

Default installations expose only `/harness-implement`, `/harness-fix`, and `/harness-investigate`. The protocols below are bundled privately inside those workflows, so agents still apply TDD, debugging, specs, QA, and review without adding those primitives to the normal command surface.

Advanced users can expose the supported primitives as standalone skills with `./setup --global --expert` or `./setup --target <path> --expert`. This mode is optional; operational CLI commands such as `harness qa`, `harness commit`, and `harness pr` remain available in both modes.

<details>
<summary><b>1. 🐛 Deterministic Debugging (<code>/harness-bug &lt;issue&gt; &lt;slug&gt;</code>)</b></summary>

Enforces a 6-phase root-cause analysis cycle inspired by Matt Pocock and engineering superpowers:
1. **Red Command**: Isolate single reproduction test or curl command.
2. **Control & Blast Radius**: Inspect recent commits, touched files, and architectural blast radius.
3. **Hypothesis**: Formulate a single falsifiable hypothesis before writing fixes.
4. **Targeted Instrumentation**: Inject tagged `[DEBUG-xxxx]` probes.
5. **Root-Cause Confirmation**: Inspect variable state and confirm causal chain.
6. **Minimal Fix & Probes Cleanup**: Apply atomic fix, remove debug probes, and verify clean git status.
</details>

<details>
<summary><b>2. 🔴 Strict TDD Loop (<code>/harness-tdd &lt;test_path&gt;</code>)</b></summary>

Enforces the Red-Green-Refactor protocol:
- **RED**: Write a failing unit/integration test capturing new requirements. Verify it fails for the right reason.
- **GREEN**: Write minimal code necessary to make the test pass.
- **REFACTOR**: Clean up implementation without altering observable behavior.
</details>

<details>
<summary><b>3. 🛡️ Static Landmine Scanner (<code>/harness-scan [--staged]</code>)</b></summary>

Scans code against custom JSON regex rules (`rules/landmines.json`):
- Detects unindexed queries, raw SQL, client-side secret leaks, and unhandled promise rejections.
- `--staged` reads staged content from the Git index, so it judges the commit rather than the working tree.
- `--branch` reads everything the branch changes since its merge base with the trunk — committed work included — which is what `harness qa all` and `harness ship` gate on. `--base <ref>` names that base for a shallow CI clone where the trunk ref is absent.
- A rule whose pattern `grep -E` cannot compile aborts the scan instead of silently never matching.
- Rules that were requested and cannot be read abort too. The built-in template is the default for a project that configured nothing, never a stand-in for a `rules/landmines.json` that has been renamed away.
- A scan that could not determine its rules or its range exits `2`, which `harness qa all` reports as a gate that **could not run**. It is never reported as a scan that passed.
- Install as a pre-commit hook via `harness scan --install-hook`.
</details>

<details>
<summary><b>4. 📐 Living Delta Specs (<code>/harness-spec &lt;create|verify|archive&gt;</code>)</b></summary>

Lightweight Spec-Driven Development (OpenSpec), with a lifecycle that closes:

```bash
harness spec create <issue_key> <slug>   # specs/delta-<issue_key>-<slug>.md
harness spec verify                      # structure, headings, no leftover placeholders
harness spec archive                     # specs/archive/<module>/ once the work is handed off
```

- Records architectural requirements, edge cases, and explicit non-goals before code.
- `create` refuses to replace a spec that already exists, and `archive` refuses an occupied
  destination or a path outside `specs/`.
- A spec is active while its work is in flight. `harness context` counts what is left in
  `specs/` and reports it as exactly that, so archiving at hand-off is what keeps the next
  run from starting on a false statement. `harness ship` names any spec still active before
  it publishes.
</details>

<details>
<summary><b>5. 🩺 Self-Healing Doctor (<code>/harness-doctor [--fix]</code>)</b></summary>

Diagnoses environment health:
- Verifies required executables, target repository health, and which agent harnesses are active.
- Reports whether each installed skill surface is still current, with a reason per drifted surface. Drift is a warning, not an error: a stale surface still works.
- Checks that the `~/.local/bin` CLI symlinks resolve to this checkout and that the directory is on `PATH`.
- Reports whether the repository's `pre-commit` hook is agent-harness's own, a foreign hook, or absent.
- Validates the resolved configuration; a configuration that does not validate is an error, not a warning.
- `--check-auth` reports whether the configured issue and CI provider CLIs are authenticated.
- `--fix` synchronizes the drifted surfaces it found. A check that could not run reports as unavailable, never as clean.
</details>

<details>
<summary><b>6. 🌳 Worktree Isolation (<code>/harness-worktree &lt;create|list&gt;</code>)</b></summary>

Manages isolated `git worktree` directories per ticket:
- Enables agents to work in parallel on separate features without dirtying your main workspace or switching active branches.
- A worktree gets its tracked files from Git, but not the installed skill surfaces — those are installation artifacts. `create` therefore reports which surfaces the new worktree carries, which it lacks, and whether the global surfaces still cover it, instead of reporting only that a directory exists.
- `harness worktree seed <path>` gives a worktree its own surfaces and `AGENTS.md` symlinks, and writes nothing else. It refuses a project that tracks its surfaces in Git, because installing over versioned bundles would rewrite them.
- `harness init` records the surfaces it installs in the target's `.gitignore`, so whether worktrees inherit the harness stops being decided by accident. The `CLAUDE.md` and `GEMINI.md` symlinks are deliberately left committable: tracking them is what carries `AGENTS.md` into every worktree for free.
</details>

<details>
<summary><b>7. 🧪 QA Orchestrator (<code>/harness-qa &lt;test|tdd|all&gt;</code>)</b></summary>

Unified interface for running test runners (`pytest`, `vitest`, `jest`, `cargo`, `go test`), linters, and type-checkers based on active project profiles.

Gates fail closed. A gate with nothing configured for it reports that it **could not run**
and exits non-zero; `harness qa all` names such gates separately from the ones that failed
and refuses to print success for either. A project that genuinely has no linter or type
checker records that as a decision rather than living with an unsatisfiable gate:

```json
{ "qa": { "lintCommand": false, "typeCheckCommand": false } }
```

Those gates then report as *declared absent* and do not fail the suite.
</details>

<details>
<summary><b>8. ⚖️ Two-Axis Code Review (<code>/harness-review</code>)</b></summary>

Performs automated two-axis code reviews:
- **Axis 1 (Engineering Standards)**: Invariants, landmines, error handling, performance regressions.
- **Axis 2 (Spec Conformance)**: Verifies all requirements in the ticket / delta spec are met.
</details>

<details>
<summary><b>9. 🔀 Conflict Resolver (<code>/harness-conflicts</code>)</b></summary>

Resolves git merge and rebase conflicts systematically by tracing the original commit intent from branch logs.
</details>

<details>
<summary><b>10. 📋 Discovery Questionnaire (<code>/harness-questionnaire</code>)</b></summary>

Transforms technical blockers or ambiguous domain decisions into structured discovery forms for external stakeholders.
</details>

<details>
<summary><b>11. 🌾 Debt Harvester (<code>/harness-debt [--json]</code>)</b></summary>

Audits and indexes pragmatic technical debt markers (`# pragmatism:`, `# defer:`, and their `//` forms) across the codebase.

A marker is a *comment*: the token has to start a line, follow only indentation, or follow whitespace on a code line. Quoted inside prose or a string literal it is not a marker and is not reported, so a project that documents its own convention — or tests it — does not inflate its own count.
- Tracked files by default, through `git grep`, so the count does not depend on which search tool happens to be installed. `--all` includes untracked files.
- `--json` emits a single array of `{file, line, text}`. A scan that could not complete exits non-zero rather than reporting zero markers.
</details>

<details>
<summary><b>12. ✍️ Conventional Commit (<code>/harness-commit &lt;build|msg&gt;</code>)</b></summary>

Formats semantic Conventional Commits (`feat:`, `fix:`, `refactor:`, `chore:`) automatically associated with ticket IDs.
</details>

<details>
<summary><b>13. 🎯 Architectural Task Planner (<code>/harness-task &lt;issue&gt; &lt;slug&gt;</code>)</b></summary>

Discovers requirements, identifies deep module seams, drafts delta specs, and sets up isolated branches.
</details>

<details>
<summary><b>14. 🧹 Code Simplifier & Complexity Reducer (<code>/harness-simplify [path]</code>)</b></summary>

Audits generated code to strip speculative abstractions, shallow wrappers, dead types, and over-engineering (YAGNI & Deep Modules) while maintaining GREEN tests.
</details>

<details>
<summary><b>15. 💬 Socratic Requirement Interrogator (<code>/harness-interview [topic]</code>)</b></summary>

Resolves architectural ambiguity by asking exactly **one structured multiple-choice question at a time** with a recommended option before drafting specs.
</details>

<details>
<summary><b>16. 🔁 Bounded Review Loop (<code>/harness-loop &lt;run_id&gt;</code>)</b></summary>

Bounds a review phase so it terminates without dropping a finding: three rounds at most, every failed round signed so an unconverging loop exits early, and every finding still open at the cap either parked with a recorded ruling or declared load-bearing. Bundled into `/harness-implement`, `/harness-fix` and `/harness-orchestrate`, which reference it rather than restating it.
</details>

---

## 🛡️ Injecting Domain Rules & Landmines

In your target repository, define custom domain rules in `rules/`:

### 1. `rules/floor.md` (Unbreakable Quality Floor)
```markdown
# Quality Floor Invariants
1. No unindexed database queries in API routes.
2. All external API integrations must use circuit breakers and retries.
3. Every database mutation must emit an audit event.
```

### 2. `rules/landmines.json` (Automated Pre-Commit Scanner)

A rule matches either file **content** through `pattern` or a repository-relative **path**
through `pathPattern` — exactly one of the two. Both are POSIX extended regular expressions
(`grep -E`); a pattern the platform's `grep` cannot compile aborts the scan instead of
silently matching nothing.

```json
[
  {
    "id": "NO_RAW_SQL",
    "name": "SQL Injection Risk",
    "pattern": "(cursor\\.execute\\(f[\"']|raw_query\\(f[\"'])",
    "fileExtensions": [".py", ".ts"],
    "level": "error",
    "message": "Raw f-string SQL query detected. Always use parameterized queries."
  },
  {
    "id": "NO_COMMITTED_SECRETS",
    "name": "Secret material committed by path",
    "pathPattern": "(^|/)([.]env([.][^/]+)?|[^/]+[.](pem|key))$",
    "excludePaths": ["*.example"],
    "level": "error",
    "message": "Environment files and key material belong in a secret manager, never in Git."
  }
]
```

`excludePaths` takes glob patterns and scopes a rule without switching it off (`vendor/*`,
`*.generated.js`, `tests/*`). A single line can be exempted in place:

```python
value = legacy_call()  # harness-ignore: NO_RAW_SQL
```

The marker works on the matching line or the line directly above it, and it silences only
the rule it names. Without an escape hatch the only way past a false positive is
`--no-verify`, which retires the whole gate rather than one line.

`ignoreCase: true` makes one rule case-insensitive. `grep -E` has no inline `(?i)` — the
validator rejects PCRE constructs — so a rule that should match `API_KEY`, `Api_Key` and
`api_key` alike declares it as a field. Leave it off where the case carries meaning: an AWS
key id is `AKIA`, a GitHub token is `ghp_`, and matching those case-insensitively would only
add false positives.

Binary files are never scanned. A finding inside one would arrive with no line number, and a
rule can only be exempted on a line.

#### The security baseline

Beneath whatever rules a project configures, the scanner always applies a built-in security
baseline: a case-insensitive credential assignment (`SEC-010`), provider-issued tokens for
GitHub, AWS, OpenAI, Slack and Google (`SEC-011`), credentials embedded in a URL or DSN
(`SEC-012`), and a PEM private-key block found by content rather than by filename
(`SEC-013`). It is deliberately quiet about interpolated values and placeholders —
`"${DB_PASSWORD}"`, `"{{ vault_token }}"`, `"<your-key>"` — because a gate that cries wolf is
answered with `--no-verify`.

The baseline exists because the scanner resolves exactly one rule file and `harness init`
copies the template into the project. Without it, improving the default rules would reach new
repositories only, and every project that had already run `init` would keep its original copy
for good.

A project disagrees with it at three grains:

```jsonc
// one line, in the source itself
password = os.environ["DB_PASSWORD"]  // harness-ignore: SEC-010

// one rule, by redefining its id in your own rules file
{ "id": "SEC-010", "name": "…", "level": "warning", "pattern": "…", "message": "…" }

// all of it, as a recorded decision
{ "profiles": { "app": { "rules": { "securityBaseline": false } } } }
```

Every scan names which of the two it read, so `using rules: ./rules/landmines.json + the
security baseline (8 rules in force)` and `(security baseline disabled by …)` are both
visible in the output rather than assumed.

The shipped rules and every recipe include a `pathPattern` rule refusing `.env` files,
private keys, and certificate bundles, with `*.example` and `*.sample` exempted.

Install as pre-commit guard:
```bash
harness scan --install-hook
```

The installed hook runs `harness scan --staged`, which reads the blobs in the Git index. A violation that is staged and then reverted in the working tree still blocks the commit, and a violation that exists only on disk does not.

If a `pre-commit` hook agent-harness did not write is already in place, installation refuses rather than replacing it, and prints the one line to add to your own hook instead:

```bash
harness scan --install-hook --force
```

`--force` replaces the existing hook after copying it to `pre-commit.harness-backup`. It refuses if that backup already exists.

---

## 💻 Multi-Call CLI Dispatcher (`harness`)

The single `harness` executable acts as a multi-call dispatcher (like `busybox` or `git`) without a language-runtime package bundle. It expects standard shell tooling plus Git and `jq`; `curl` is required for optional AI and network integrations.

- **Primary command:** `harness <command>` (aliases: `agh`, `agent-harness`).
- **Dynamic profile resolution:** Auto-detects the active profile based on the current directory or explicit `--profile <name>`.
- **Custom aliases:** Define a custom alias in `stack.config.json` (e.g. `"cliAlias": "backend"`):
  - Typing `backend doctor` or `backend qa` automatically targets that specific profile.

### ⚙️ Which configuration is in force

Resolution stops at the first file a project actually carries, in this order:
`harness.config.json`, `.harnessrc.json`, `stack.config.json`, `.stackrc.json`,
`config.json` in the current directory, then `config.json` at the harness root, then
`~/.config/agent-harness/config.json`. A repository with none of them resolves to the
built-in defaults under the profile name `default`.

`config.example.json` is **documentation** and is not part of that order. Copy it, do not
rely on it.

```bash
harness config validate
```

reports the file that was resolved, the active profile and how it was chosen, and every
structural problem it can determine from `schema.json`: invalid JSON, a key whose type the
schema contradicts, a key the schema does not describe, a `defaultProfile` naming no
profile, and a `targetRepoPath` that does not exist. It is a structural walk of the schema
rather than a JSON Schema engine, and it prints which checks it did not perform.

### 🔄 Keeping installed surfaces current

Workflow bundles are copied into each runtime's skills directory, so upgrading agent-harness does not update a surface that was installed earlier. Every surface records what it is in a `.agent-harness-surface.json` manifest — version, mode, runtime, and a digest per bundle — which makes that answerable offline:

```bash
harness sync --check     # report drift and exit non-zero if any surface is stale
harness sync             # repair the global surfaces and the current repository's
```

`harness sync` repairs; it never installs a new surface — that is `harness init`. It writes only to surfaces that already exist and are managed, names every one of them before writing, preserves the mode each was installed in (an expert surface stays expert), and is undone by `./setup --rollback` like any other installation. `--target <path>` acts on one repository and `--global` on the global surfaces alone.

### 🚢 Publishing a branch (`harness ship`)

```bash
harness ship                 # QA, ask, push, open a pull request into the trunk
harness ship release/5.30    # …into another branch
harness ship --dry-run       # report every decision and change nothing
harness ship --yes           # confirm the push in advance
```

Publication is outward-facing and effectively irreversible, so `ship` decides what it is
about to publish before it publishes anything. It refuses to publish the branch it is
targeting, a detached `HEAD`, a branch with no commits ahead of its target, and uncommitted
changes to tracked files that a push would not carry — naming what it found and leaving the
repository untouched. Untracked files are reported rather than refused.

It asks before pushing, and refuses where there is no terminal to ask on; `--yes` is how a
human confirms in advance. An agent must not pass it on its own initiative. `ship` creates
no commits. If the push succeeds but no pull request is opened, it exits non-zero and says
which half happened rather than reporting a completed ship.

### 📌 Which version is installed, and upgrading

```bash
harness version          # the version, the checkout it runs from, and that checkout's revision
harness upgrade --check  # report currency and surface drift; changes nothing
harness upgrade          # fast-forward the checkout, then re-sync every managed surface
```

Every surface manifest records a version and `harness sync` compares against it, so being
able to ask which version is actually installed is part of that model rather than a
convenience. `harness version` also names the checkout, because a CLI symlink can point
anywhere, and its revision, because a released version and a working checkout on the same
version number are not the same thing.

`harness upgrade` refuses a checkout that is not a Git clone, one with a detached `HEAD`,
one tracking no upstream, and one with uncommitted changes to tracked files. It
fast-forwards only. `--check` is a report rather than a gate: it names whatever it could
not determine and still exits `0`. The gate for surface currency is `harness sync --check`.

### 🐚 Shell Autocompletion (Zsh & Bash)

Enable instant tab completion for `harness` / `agh`:
```bash
harness completion install
```

It writes a Zsh completion to `~/.zsh/completion/_harness` and a Bash completion to
`~/.local/share/bash-completion/completions/harness`, and prints how to load each.

---

## 🍳 Ready-to-Use Recipes

Jumpstart your stack with production-ready presets:
- 🐍 **`recipes/python-fastapi/`**: Async discipline, Pydantic v2 validation, SQLAlchemy patterns.
- 🔷 **`recipes/typescript-fullstack/`**: Strict null checks, Zod boundary validation, immutable state.
- 🐹 **`recipes/go-microservices/`**: Context propagation, explicit error wrapping, goroutine safety.

*See [docs/RECIPES.md](docs/RECIPES.md) for how to use and contribute new recipes.*

---

## 🏛️ Architecture & System Design

For a deep dive into sub-second context signals, multi-harness synchronization, and POSIX core architecture, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## 🙏 Acknowledgements & Provenance

`agent-harness` is an independent implementation that synthesizes proven ideas from the open-source agent engineering community. In particular:

- **[addyosmani/agent-skills](https://github.com/addyosmani/agent-skills)** — workflow-oriented skills, explicit verification gates, and anti-rationalization safeguards.
- **[obra/superpowers](https://github.com/obra/superpowers)** — strict Red-Green-Refactor discipline, systematic debugging, and isolated worktree workflows.
- **[mattpocock/skills](https://github.com/mattpocock/skills)** — tight red-capable feedback loops, ranked falsifiable hypotheses, and tagged diagnostic instrumentation.
- **[Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec)** — Spec-Driven Development, living specifications, and delta-based requirements.
- **[ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd)** — action-first communication, visible state anchors, and cognitive-load reduction.

These projects are sources of inspiration and adapted engineering patterns; they are not runtime dependencies of `agent-harness`. See [Provenance and Acknowledgements](docs/PROVENANCE.md) for the exact relationships, source snapshots, and licensing policy.

---

## 🤝 Contributing & Community

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community standards.

```bash
# Verify all scripts and skill frontmatter
./setup --verify

# Lint every shell entry point
npm run lint

# Run the full test suite (CLI, transaction library, transactional installer)
npm test
```

Every pull request runs both workflows, whatever branch it targets. The `pull_request`
trigger carries no base-branch filter on purpose: a pull request stacked on another, or
aimed at a `release/*` branch, used to run no job at all — and GitHub renders zero checks
as an absence rather than a failure, so a pull request nothing had verified was
indistinguishable from one that had passed everything. `push` stays scoped to `main`,
since pull requests are where the coverage has to be universal.

---

## 📄 License

Distributed under the [MIT License](LICENSE).
