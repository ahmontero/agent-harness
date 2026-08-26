---
name: conflicts
description: Resolves in-progress git merge and rebase conflicts by tracing intent from original commits and issue context.
---

# /conflicts: Intent-Driven Merge Conflict Resolver

1. Identifies conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`).
2. Inspects git history and intent of both incoming and current commits.
3. Resolves conflicts preserving both sides' semantic intent without regressions.
4. Validates resolution by running `harness qa test`.
