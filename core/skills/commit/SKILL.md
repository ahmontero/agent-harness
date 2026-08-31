---
name: harness-commit
description: Builds and validates Conventional Commit messages prefixed with the active issue key.
argument-hint: "build <type> \"<message>\" | check [commit_hash]"
---

# /harness-commit: Conventional Commit Builder

Formats commit messages according to Conventional Commits standards with issue keys extracted from the active branch:

```bash
harness commit build feat "add JWT authentication middleware"
# Output: feat(PROJ-123): add JWT authentication middleware
```
