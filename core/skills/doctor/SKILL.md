---
name: harness-doctor
description: Diagnoses and self-heals the engineering environment: CLI dependencies and symlinks, installed skill surfaces, the landmine pre-commit hook, and the resolved configuration.
argument-hint: "[--fix] [--check-auth]"
---

# /harness-doctor: Environment Health & Self-Healing

Diagnoses, in order: required and optional executables; which agent harnesses are active;
the target repository's `AGENTS.md`; whether each installed skill surface is still current;
whether the `~/.local/bin` CLI symlinks resolve to this checkout and are on `PATH`; whether
the repository's `pre-commit` hook is agent-harness's own, a foreign hook, or absent; and
whether the resolved configuration passes `harness config validate`.

Drift and missing optional tooling are warnings and leave the exit status at `0`. A
configuration that does not validate, a broken CLI symlink, or a missing required tool is
an error and exits non-zero. A check that could not run is reported as unavailable, never
as clean.

```bash
# Diagnostic check
harness doctor

# Self-heal what can be repaired (AGENTS.md, drifted skill surfaces)
harness doctor --fix

# Also report whether the configured issue and CI provider CLIs are authenticated
harness doctor --check-auth
```
