# 🍳 Recipes Guide & Authoring Reference

Recipes provide ready-to-use, framework-specific quality floors, static landmines, and test configurations for `agent-harness`.

---

## 📦 Available Recipes

| Recipe | Stack | Highlights |
| :--- | :--- | :--- |
| **`python-fastapi`** | Python 3.11+, FastAPI, Pydantic v2, SQLAlchemy | Async route discipline, Pydantic boundary validation, no raw SQL, pytest-asyncio integration. |
| **`typescript-fullstack`**| TypeScript, Node.js / Next.js, Zod, Vitest | Strict null checks, client-side secret protection, immutable state updates, Zod schema parsing. |
| **`go-microservices`** | Go 1.21+, Standard Library / Chi, Zap | Context propagation, explicit error wrapping (`%w`), graceful shutdown, goroutine leak protection. |

---

## 🚀 Applying a Recipe

When initializing a new or existing repository:

```bash
# Apply a specific recipe during initialization
harness init --recipe python-fastapi

# Or with ./setup directly
./setup --target ~/projects/my-api --recipe python-fastapi
```

---

## 🛠️ How to Create a New Recipe (3-Minute Guide)

A recipe lives in `recipes/<recipe-name>/` and requires only 3 files:

```text
recipes/<recipe-name>/
├── stack.config.json       # Framework QA commands, file detection, and aliases
└── rules/
    ├── floor.md            # Unbreakable quality floor & architectural invariants
    └── landmines.md        # Common antipatterns and pitfalls for LLMs
```

### 1. `stack.config.json`
Define the QA runners, linters, and detection heuristics:
```json
{
  "profiles": {
    "my-stack": {
      "cliAlias": "mystack",
      "displayName": "My Custom Stack",
      "detect": {
        "files": ["mix.exs", "Cargo.toml"]
      },
      "qa": {
        "testRunner": "cargo",
        "testCommand": "cargo test",
        "tddCommand": "cargo test -- {path}",
        "lintCommand": "cargo clippy -- -D warnings"
      }
    }
  }
}
```

### 2. `rules/floor.md`
List 3-5 non-negotiable architectural invariants:
```markdown
# Architectural Invariants
1. All database queries must be wrapped in transactions.
2. HTTP handlers must not contain direct business logic.
3. Every public function must have structured telemetry tracing.
```

### 3. `rules/landmines.md` & `rules/landmines.json`
Document specific pitfalls that AI agents often fall into, along with regex patterns for `harness scan`:
```json
[
  {
    "id": "NO_SYNC_IO",
    "name": "Synchronous I/O in Async Function",
    "pattern": "fs\\.readFileSync|requests\\.get",
    "fileExtensions": [".ts", ".py"],
    "level": "error",
    "message": "Do not perform blocking synchronous I/O inside asynchronous loops."
  }
]
```

Submit your recipe via a Pull Request to share it with the community!
