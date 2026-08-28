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
        Skills["19 Core Agent Skills<br>(3 Workflows + TDD, Debug, Review, Specs, QA)"]
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
- Creates synchronized symbolic links across `.gemini/skills`, `.claude/skills`, `.codex/skills`, `.cursor/rules`, and `.agents/skills`.
- Single source of truth for living specs and domain rules.

### 3. Sub-Second Context Extraction
- `harness context --json` extracts the active profile, repository, branch/trunk, dirty state, configured test runner and issue provider, plus active-spec and debt counts in a compact JSON signal.
