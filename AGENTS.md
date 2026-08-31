# AGENTS.md — Repository AI Engineering Instructions

Universal AI Agent Harness guidelines for this repository.
Synchronized across **Google Antigravity**, **Claude Code**, **OpenAI Codex**, **Cursor**, and **.agents**.

---

## 🛡️ Engineering & Quality Floor

1. **Test-Driven Discipline**: Never write implementation code without a failing test first. Use the `/harness-tdd` or `/harness-bug` skill.
2. **Deterministic Debugging**: Never guess or patch blindly. Follow the 6-phase debugging loop (`/harness-bug`).
3. **Domain Landmines**: Before making changes, inspect `rules/landmines.md` and ensure `harness scan` passes.
4. **Living Specs**: Document significant features and architectural changes in `specs/delta-*.md` before implementation (`/harness-spec` or `/harness-task`).
5. **Clean Workspaces**: Use `harness worktree` to isolate changes without polluting the main working tree.
6. **Simplicity First**: Remove speculative abstractions and dead code before shipping (`/harness-simplify`).

---

## ⚡ High-Signal & Action-First Communication

1. **Action-First (No Fluff)**: Lead with the concrete action (command, path, exact snippet). Put explanations and context at the end.
2. **Turn State Anchors**: In multi-step workflows, maintain a clear state indicator: `[Status: Step X/Y | Current Action | Next Action]`.
3. **Anti-Tangent Discipline**: Never derail the main task on newly discovered side issues. Capture them immediately as `# pragmatism:` or `harness debt`.
4. **Anti-Rationalization**: Obey all quality gates strictly. Never bypass tests, specs, or scans under excuses of urgency or triviality.
