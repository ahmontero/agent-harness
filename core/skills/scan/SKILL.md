---
name: harness-scan
description: Runs static Landmine & Security scanner against staged files or working diff using JSON regex rules.
argument-hint: "[--staged|--diff|--branch|--all] [--base <ref>] [--install-hook]"
---

# /harness-scan: Static Landmine & Security Scanner

Scans staged code against domain landmines defined in `rules/landmines.json`.

```bash
harness scan --staged        # Scan staged files (default)
harness scan --diff          # Scan unstaged diff
harness scan --branch        # Scan every change this branch makes since the trunk
harness scan --base <ref>    # With --branch, name the base instead of detecting it
harness scan --all           # Scan all tracked files
harness scan --install-hook  # Install pre-commit guard
```
