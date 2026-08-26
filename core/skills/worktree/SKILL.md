---
name: worktree
description: Manages isolated git worktree directories for tickets/features without dirtying the main working tree.
argument-hint: "create <type> <issue_key> <slug> | list | remove <issue_key>"
---

# /worktree: Workspace Isolation

Allows parallel development on multiple branches simultaneously using git worktree.

```bash
# Create worktree in ../<repo>-<issue>
harness worktree create feat PROJ-123 add-auth

# List active worktrees
harness worktree list

# Clean up finished worktree
harness worktree remove PROJ-123
```
