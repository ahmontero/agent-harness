# 🏛️ Architecture & System Design

`agent-harness` is designed as a **zero-dependency, sub-second engineering harness** that operates across any AI coding agent runtime.

---

## 🧩 Architectural Layers

```mermaid
flowchart TD
    subgraph Engine["⚡ Core Agnostic Engine"]
        CLI["bin/harness<br>(Multi-Call Dispatcher & POSIX Shell Core)"]
        Scanner["Static Landmine Scanner<br>(rules/landmines.json + Regex AST Engine)"]
        Context["Sub-Second Context Engine<br>(<0.5s JSON Signal Generator)"]
        Worktree["Git Worktree Manager<br>(Isolated Per-Ticket Workspaces)"]
        Skills["14 Core Agent Skills<br>(TDD, 6-Phase Debug, Two-Axis Review, Living Specs)"]
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
```

---

## ⚡ Core Design Principles

### 1. Zero External Dependencies
- Written entirely in clean, portable POSIX/Bash (`set -eo pipefail`).
- No heavy runtime overhead, node bundles, or Python dependencies required to run the CLI or hooks.
- Fast startup time (<50ms).

### 2. Universal Multi-Harness Federation
- Creates synchronized symbolic links across `.gemini/skills`, `.claude/skills`, `.codex/skills`, `.cursor/rules`, and `.agents/skills`.
- Single source of truth for living specs and domain rules.

### 3. Sub-Second Context Extraction
- `harness context --json` extracts git state, active branch, ticket metadata, modified files, and applicable floor rules in `< 500ms`, feeding agents exact signals without consuming tens of thousands of prompt tokens.
