---
name: doctor
description: Diagnoses and self-heals the engineering environment, agent harness symlinks, CLI dependencies, and git hooks.
argument-hint: "[--fix] [--check-auth]"
---

# /doctor: Environment Health & Self-Healing

Diagnoses missing tools, broken harness symlinks, unconfigured hooks, and outdated configs.

```bash
# Diagnostic check
harness doctor

# Self-heal broken configs and symlinks
harness doctor --fix
```
