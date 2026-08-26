# AGENTS.md — Repository AI Engineering Instructions

Universal AI Agent Harness guidelines for this repository.
Synchronized across **Google Antigravity**, **Claude Code**, **OpenAI Codex**, **Cursor**, and **.agents**.

---

## 🛡️ Engineering & Quality Floor

1. **Test-Driven Discipline**: Never write implementation code without a failing test first. Use the `/tdd` or `/bug` skill.
2. **Deterministic Debugging**: Never guess or patch blindly. Follow the 6-phase debugging loop (`/bug`).
3. **Domain Landmines**: Before making changes, inspect `rules/landmines.md` and ensure `harness scan` passes.
4. **Living Specs**: Document significant features and architectural changes in `specs/delta-*.md` before implementation (`/spec` or `/task`).
5. **Clean Workspaces**: Use `harness worktree` to isolate changes without polluting the main working tree.
