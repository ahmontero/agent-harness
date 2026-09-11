# 🏛️ Architecture & System Design

`agent-harness` is designed as a **small, shell-native engineering harness** that operates across AI coding agent runtimes without a language-runtime package bundle.

---

## 🧩 Architectural Layers

```mermaid
flowchart TD
    subgraph Engine["⚡ Core Agnostic Engine"]
        CLI["bin/harness<br>(Multi-Call Dispatcher & Bash Core)"]
        Scanner["Static Landmine Scanner<br>(rules/landmines.json + Regex AST Engine)"]
        Context["Sub-Second Context Engine<br>(<0.5s JSON Signal Generator)"]
        Worktree["Git Worktree Manager<br>(Isolated Per-Ticket Workspaces)"]
        Receipts["Private Execution Receipts<br>(Git metadata + JSONL lifecycle events)"]
        Skills["Namespaced Skill Surface<br>(3 harness-* Workflows + Private Protocol Bundles)"]
    end

    subgraph Federation["🔄 Multi-Harness Bridge"]
        Gemini[".gemini/ (Google Antigravity)"]
        Claude[".claude/ (Claude Code)"]
        Cursor[".cursor/ (Cursor Agent)"]
        Codex[".codex/ (OpenAI Codex)"]
        Agents[".agents/ & AGENTS.md (Open Standard)"]
    end

    subgraph ProjectSpace["⚙️ Injected Target Repository"]
        Config["stack.config.json"]
        Floor["rules/floor.md"]
        Landmines["rules/landmines.md"]
    end

    CLI --> Federation
    Federation --> ProjectSpace
    Context --> ProjectSpace
    Scanner --> ProjectSpace
    Skills --> Receipts
```

---

## ⚡ Core Design Principles

### 1. Minimal System Dependencies
- Written in Bash with no Node, Python, or compiled runtime bundle.
- Requires Git and `jq`; network and optional AI integrations additionally use `curl`.
- Keeps startup and installation overhead small by relying on standard system tooling.

### 2. Universal Multi-Harness Federation
- Installs `harness-implement`, `harness-fix`, and `harness-investigate` across `.gemini/skills`, `.claude/skills`, `.codex/skills`, and `.agents/skills`, plus runtime-specific rule directories such as `.cursor/rules`.
- The catalog's `harness` namespace is applied to every published directory and `SKILL.md` name; `--expert` exposes primitives through the same namespace.
- Each workflow bundle carries its required private protocol references, while the canonical catalog remains the single source of truth for public, internal, and removed skills.

### 3. Per-Runtime Skill Gating

Most skills are identical in every runtime, but a workflow may depend on a primitive only one runtime exposes. `core/skills/catalog.json` carries a `runtimes` map for that case: a public workflow listed there reaches only the runtimes it names, and a workflow absent from the map reaches all of them. `install.sh` resolves a runtime label for each destination directory and filters workflow installation by it.

Removal stays unconditional while installation is filtered. The installer clears every managed skill path in the catalog before installing the permitted set, so a workflow that becomes gated after a previous installation disappears from the disallowed runtimes on the next run, with no migration step. The compatibility matrix asserts both halves: presence where a workflow is declared, and absence everywhere else.

Internal primitives are never gated. Expert mode continues to expose all of them in every runtime.

### 4. Recorded Surface Identity

A public workflow is **copied** into each runtime's skills directory; an expert primitive is **symlinked** to the source tree. The asymmetry matters: a symlink follows the source and cannot go stale, while a copy is a snapshot that upgrading the harness does not touch.

Each surface therefore carries a `.agent-harness-surface.json` manifest recording the schema, namespace, harness version, installed mode, runtime, and one entry per skill — `bundle` with a digest, or `symlink` without one. The digest is `git hash-object` over the bundle's content with every file preceded by its relative path, so a reference republished under a new name signs differently from the original.

`core/scripts/lib/surface.sh` holds that reasoning once, and the installer, `harness sync`, and `harness doctor` all read it from there. Two implementations of "what should this surface contain?" would eventually disagree, and the disagreement would surface as a directory reported current because the checker forgot a rule the installer applies.

### 5. Sub-Second Context Extraction
- `harness context --json` extracts the active profile, repository, branch/trunk, dirty state, configured test runner and issue provider, plus active-spec and debt counts in a compact JSON signal.
