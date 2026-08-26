---
name: ship
description: Runs full pre-flight QA verification, builds conventional commit, and opens a Pull Request on GitHub/GitLab.
argument-hint: "[target_branch]"
---

# /ship: Pre-Flight Verification & PR Creation

Executes the complete release flow:
1. Runs `harness qa all` (Landmine scan + Linters + Tests).
2. Pushes branch to remote origin.
3. Opens Pull Request via `gh pr create` or `glab mr create`.
