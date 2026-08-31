---
name: harness-task
description: Plans, designs, and creates branches/worktrees for a new task or feature with clear architectural seams.
argument-hint: "[Issue Key / ID] [Task Slug]"
---

# /harness-task: Architectural Planning & Task Discovery

This skill acts as the **Lead Architect**, guiding the planning, design, and worktree creation for new features or refactors.

---

## 🎯 Protocol: 4-Step Discovery & Design Loop

1. **Context & Requirement Ingestion**:
   - Extract issue details and requirement invariants.
   - Run `harness context` to inspect active branch, trunk, and open specs.

2. **Architectural Seams & Boundary Definition**:
   - Identify existing interfaces, modules, and data models to modify.
   - Check `rules/floor.md` and `rules/landmines.md` to prevent anti-patterns.

3. **Delta Spec Creation**:
   ```bash
   harness spec create <issue_key> <slug>
   ```

4. **Workspace Isolation (Branch or Worktree)**:
   ```bash
   # Create isolated worktree:
   harness worktree create feat <issue_key> <slug>
   # Or create standard git branch:
   harness branch create feat <issue_key> <slug>
   ```
