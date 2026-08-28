# 🚀 agent-harness

<p align="center">
  <a href="package.json"><img src="https://img.shields.io/badge/version-1.0.0-blue.svg" alt="Version" /></a>
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
- [🚦 Three Engineering Workflows](#-three-engineering-workflows)
- [🧠 The 19 Standard Agent Skills](#-the-19-standard-agent-skills)
- [🛡️ Injecting Domain Rules & Landmines](#️-injecting-domain-rules--landmines)
- [💻 Multi-Call CLI Dispatcher (`harness`)](#-multi-call-cli-dispatcher-harness)
- [🍳 Ready-to-Use Recipes](#-ready-to-use-recipes)
- [🏛️ Architecture & System Design](#️-architecture--system-design)
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
   1. Strictly enforced Red-Green-Refactor loop (`/tdd`) with Anti-Rationalization Gates.
   2. Automatic branch/worktree isolation (`/worktree`) keeps your workspace clean.
   3. Anti-Rationalization Matrices cut off LLM excuses across all critical engineering skills.
   4. Static JSON AST/regex scanner (`/scan`) prevents known landmines before commit.
   5. Matt Pocock-inspired 6-Phase Deterministic Debugging (`/bug`) with tagged probe instrumentation.
   6. Action-First & State-Anchored communication with automatic debt harvesting (`/debt`).
```

---

## 🌐 Universal Multi-Harness Compatibility

`agent-harness` unifies your engineering standards across every major agent runtime:

| AI Runtime / IDE | Auto-Linked Skills | Quality Floor & Rules | Pre-Commit Scanner | Worktree Isolation | Sub-Second Context (<1s) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Google Antigravity** | ✅ (`.gemini/skills`) | ✅ (`.gemini/rules`) | ✅ | ✅ | ✅ (`harness context`) |
| **Claude Code** | ✅ (`.claude/skills`) | ✅ (`.claude/rules`) | ✅ | ✅ | ✅ (`harness context`) |
| **Cursor Agent** | ✅ (`.agents/skills`) | ✅ (`.cursor/rules`) | ✅ | ✅ | ✅ (`harness context`) |
| **OpenAI Codex** | ✅ (`.codex/skills`) | ✅ (`.codex/rules`) | ✅ | ✅ | ✅ (`harness context`) |
| **Generic (.agents)** | ✅ (`.agents/skills`) | ✅ (`.agents/rules`) | ✅ | ✅ | ✅ (`harness context`) |

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
```

### 2. Initialize in Any Existing Project

```bash
cd ~/projects/my-awesome-app

# Run with harness CLI (or npx @ahmontero/agent-harness)
harness init
```

`harness` will automatically:
- Detect your language and test runner (`pytest`, `vitest`, `jest`, `cargo`, `go`).
- Generate `stack.config.json` and a starter `rules/` directory.
- Link agent skills through `.gemini`, `.claude`, `.codex`, and `.agents`, plus runtime-specific rule directories including `.cursor/rules`.

---

## 🚦 Three Engineering Workflows

Most work starts with one of three intent-level workflows. They compose the primitive skills below and preserve their quality gates:

```text
/implement <requirement>     Build or change behavior through spec-aware TDD, QA, and review.
/fix <defect>                Reproduce, prove root cause, add a regression test, and apply a surgical fix.
/investigate <question>      Gather evidence, compare options, recommend, and stop without editing.
```

`/implement` and `/fix` produce verified working-tree changes but never publish them without an explicit request. `/investigate` is read-only and cannot silently transition into implementation.

### Local execution receipts

The workflows record a small JSONL lifecycle receipt inside the repository's private Git metadata. Nothing is added to the working tree or sent remotely, and the schema does not accept prompts, code, file paths, secrets, or free-form evidence.

```bash
run_id="$(harness receipt start implement --issue PROJ-123)"
harness receipt phase "${run_id}" tdd passed
harness receipt phase "${run_id}" qa passed
harness receipt finish "${run_id}" completed
```

Receipts live under `.git/agent-harness/runs/`, are shared across the repository's worktrees, and provide the input contract for future local statistics.

---

## 🧠 The 19 Standard Agent Skills

<details>
<summary><b>1. 🐛 Deterministic Debugging (<code>/bug &lt;issue&gt; &lt;slug&gt;</code>)</b></summary>

Enforces a 6-phase root-cause analysis cycle inspired by Matt Pocock and engineering superpowers:
1. **Red Command**: Isolate single reproduction test or curl command.
2. **Control & Blast Radius**: Inspect recent commits, touched files, and architectural blast radius.
3. **Hypothesis**: Formulate a single falsifiable hypothesis before writing fixes.
4. **Targeted Instrumentation**: Inject tagged `[DEBUG-xxxx]` probes.
5. **Root-Cause Confirmation**: Inspect variable state and confirm causal chain.
6. **Minimal Fix & Probes Cleanup**: Apply atomic fix, remove debug probes, and verify clean git status.
</details>

<details>
<summary><b>2. 🔴 Strict TDD Loop (<code>/tdd &lt;test_path&gt;</code>)</b></summary>

Enforces the Red-Green-Refactor protocol:
- **RED**: Write a failing unit/integration test capturing new requirements. Verify it fails for the right reason.
- **GREEN**: Write minimal code necessary to make the test pass.
- **REFACTOR**: Clean up implementation without altering observable behavior.
</details>

<details>
<summary><b>3. 🛡️ Static Landmine Scanner (<code>/scan [--staged]</code>)</b></summary>

Scans code against custom JSON regex rules (`rules/landmines.json`):
- Detects unindexed queries, raw SQL, client-side secret leaks, and unhandled promise rejections.
- Install as a pre-commit hook via `harness scan --install-hook`.
</details>

<details>
<summary><b>4. 📐 Living Delta Specs (<code>/spec &lt;create|status&gt;</code>)</b></summary>

Lightweight Spec-Driven Development (OpenSpec):
- Creates living specifications (`specs/<issue>-<slug>/spec.md`).
- Records architectural requirements, edge cases, and explicit non-goals.
</details>

<details>
<summary><b>5. 🩺 Self-Healing Doctor (<code>/doctor [--fix]</code>)</b></summary>

Diagnoses environment health:
- Verifies PATH executables, symlink integrity across AI harnesses, test runner health, and Git configuration.
</details>

<details>
<summary><b>6. 🌳 Worktree Isolation (<code>/worktree &lt;create|list&gt;</code>)</b></summary>

Manages isolated `git worktree` directories per ticket:
- Enables agents to work in parallel on separate features without dirtying your main workspace or switching active branches.
</details>

<details>
<summary><b>7. 🧪 QA Orchestrator (<code>/qa &lt;test|tdd|all&gt;</code>)</b></summary>

Unified interface for running test runners (`pytest`, `vitest`, `jest`, `cargo`, `go test`), linters, and type-checkers based on active project profiles.
</details>

<details>
<summary><b>8. ⚖️ Two-Axis Code Review (<code>/review</code>)</b></summary>

Performs automated two-axis code reviews:
- **Axis 1 (Engineering Standards)**: Invariants, landmines, error handling, performance regressions.
- **Axis 2 (Spec Conformance)**: Verifies all requirements in the ticket / delta spec are met.
</details>

<details>
<summary><b>9. 🔀 Conflict Resolver (<code>/conflicts</code>)</b></summary>

Resolves git merge and rebase conflicts systematically by tracing the original commit intent from branch logs.
</details>

<details>
<summary><b>10. 📋 Discovery Questionnaire (<code>/questionnaire</code>)</b></summary>

Transforms technical blockers or ambiguous domain decisions into structured discovery forms for external stakeholders.
</details>

<details>
<summary><b>11. 🌾 Debt Harvester (<code>/debt [--json]</code>)</b></summary>

Audits and indexes pragmatic technical debt markers (`# pragmatism:`, `# defer:`) across the codebase.
</details>

<details>
<summary><b>12. ✍️ Conventional Commit (<code>/commit &lt;build|msg&gt;</code>)</b></summary>

Formats semantic Conventional Commits (`feat:`, `fix:`, `refactor:`, `chore:`) automatically associated with ticket IDs.
</details>

<details>
<summary><b>13. 🚢 Pre-Flight Ship (<code>/ship</code>)</b></summary>

Runs full QA validation, checks git status, and opens a Pull Request on GitHub or GitLab.
</details>

<details>
<summary><b>14. 🎯 Architectural Task Planner (<code>/task &lt;issue&gt; &lt;slug&gt;</code>)</b></summary>

Discovers requirements, identifies deep module seams, drafts delta specs, and sets up isolated branches.
</details>

<details>
<summary><b>15. 🧹 Code Simplifier & Complexity Reducer (<code>/simplify [path]</code>)</b></summary>

Audits generated code to strip speculative abstractions, shallow wrappers, dead types, and over-engineering (YAGNI & Deep Modules) while maintaining GREEN tests.
</details>

<details>
<summary><b>16. 💬 Socratic Requirement Interrogator (<code>/interview [topic]</code>)</b></summary>

Resolves architectural ambiguity by asking exactly **one structured multiple-choice question at a time** with a recommended option before drafting specs.
</details>

<details>
<summary><b>17. 🛠️ Feature Delivery Workflow (<code>/implement [requirement]</code>)</b></summary>

Composes discovery, isolation, specification, TDD, simplification, QA, and review for intentional behavior changes.
</details>

<details>
<summary><b>18. 🩹 Root-Cause Fix Workflow (<code>/fix [defect]</code>)</b></summary>

Requires deterministic reproduction and confirmed root cause before regression TDD and a minimal production fix.
</details>

<details>
<summary><b>19. 🔎 Evidence-to-Decision Workflow (<code>/investigate [question]</code>)</b></summary>

Inspects the codebase and relevant evidence, compares options, recommends a path, and stops without implementation.
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
```json
[
  {
    "id": "NO_RAW_SQL",
    "name": "SQL Injection Risk",
    "pattern": "(cursor\\.execute\\(f[\"']|raw_query\\(f[\"'])",
    "fileExtensions": [".py", ".ts"],
    "level": "error",
    "message": "Raw f-string SQL query detected. Always use parameterized queries."
  }
]
```

Install as pre-commit guard:
```bash
harness scan --install-hook
```

---

## 💻 Multi-Call CLI Dispatcher (`harness`)

The single `harness` executable acts as a multi-call dispatcher (like `busybox` or `git`) without a language-runtime package bundle. It expects standard shell tooling plus Git and `jq`; `curl` is required for optional AI and network integrations.

- **Primary command:** `harness <command>` (aliases: `agh`, `agent-harness`).
- **Dynamic profile resolution:** Auto-detects the active profile based on the current directory or explicit `--profile <name>`.
- **Custom aliases:** Define a custom alias in `stack.config.json` (e.g. `"cliAlias": "backend"`):
  - Typing `backend doctor` or `backend qa` automatically targets that specific profile.

### 🐚 Shell Autocompletion (Zsh & Bash)

Enable instant tab completion for `harness` / `agh`:
```bash
harness completion install
```

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

## 🤝 Contributing & Community

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community standards.

```bash
# Verify all scripts and skill frontmatter
./setup --verify

# Run test suite
bash test/test_cli.sh
```

---

## 📄 License

Distributed under the [MIT License](LICENSE).
