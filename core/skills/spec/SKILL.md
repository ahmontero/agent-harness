---
name: spec
description: Manages Spec-Driven Development (OpenSpec / Living Delta Specs) lifecycle for features and modules.
argument-hint: "status | create <issue_key> <slug> | verify [path]"
---

# /spec: Spec-Driven Development & Living Delta Specs

Manages the lifecycle of specifications before, during, and after code changes.

```bash
# 1. Check open specs
harness spec status

# 2. Create a new delta spec
harness spec create <issue_key> <slug>

# 3. Verify compliance
harness spec verify specs/delta-<issue_key>-<slug>.md
```
