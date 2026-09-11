---
name: harness-worktree
description: Manages isolated git worktree directories for tickets/features without dirtying the main working tree.
argument-hint: "create <type> <issue_key> <slug> | list | seed <path> | remove <issue_key>"
---

# /harness-worktree: Workspace Isolation

Allows parallel development on multiple branches simultaneously using git worktree.

```bash
# Create worktree in ../<repo>-<issue>
harness worktree create feat PROJ-123 add-auth

# List active worktrees
harness worktree list

# Clean up finished worktree
harness worktree remove PROJ-123
```

A worktree gets its tracked files from Git. It cannot get the installed skill
surfaces that way, because those are installation artifacts rather than versioned
files, so `create` reports which surfaces the new worktree carries and which it does
not — and whether the global surfaces still cover it.

```bash
# Give a worktree its own surfaces, pinned to this checkout
harness worktree seed ../my-project-PROJ-123
```

Seeding writes the four skill surfaces and the `CLAUDE.md` / `GEMINI.md` symlinks, and
nothing else. It refuses a project that tracks its surfaces in Git: those bundles carry
the managed marker, so installing over them would rewrite versioned files.
